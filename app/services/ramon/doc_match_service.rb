# Anexo (imagem/arquivo) chega numa conversa com lead + checklist de docs
# pendente → pergunta ao LLM qual item do checklist o arquivo provavelmente é.
# Com ANTHROPIC_API_KEY no servidor, foto/PDF vão pro Claude Haiku 5.5, que VÊ o
# arquivo; sem ela (ou outro tipo/grande demais), o copiloto só tem nome + tipo +
# fim da conversa. Assinatura do Claude (VPS) fica fora — termos, ver LlmEscolha.
# Com visão marca o item como recebido direto; sem visão — ou em lead ganho fora da etapa Documentos — grava
# só a sugestão em custom_attributes['doc_sugestao'] pra confirmação humana no painel.
# Chave RAMON_ETAPA_DOCUMENTOS ligada (spec Etapa Documentos §5): CNIS só o completo — o resumido não marca e vira
# alerta (doc_alertas.cnis_resumido) que o agente lê para pedir o certo; em Documentos, cada marcação avisa quem confere.
class Ramon::DocMatchService
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você recebe um checklist de documentos de um caso previdenciário, os dados de um
    arquivo que o cliente acabou de enviar (às vezes o próprio arquivo) e o fim da
    conversa. Aponte QUAL item do checklist o arquivo provavelmente é. Responda APENAS
    um JSON válido (sem markdown): {"item_id": <id do item>} ou {"item_id": null} se
    não der pra afirmar. Na dúvida, responda null — nunca chute.
  PROMPT
  # Só com a chave ligada (desligada, o prompt é o de antes). Os nomes das opções vêm da pesquisa do Meu INSS (spec §3).
  PROMPT_CNIS = <<~PROMPT.freeze
    Se o item for o CNIS e o arquivo for o CNIS RESUMIDO ("Relações Previdenciárias" sem remunerações, ou "Ano Civil"),
    responda {"item_id": <id do item>, "cnis_resumido": true}. O completo tem "Remunerações" no título.
  PROMPT
  ALERTA_CNIS = 'O CNIS recebido é o resumido: pedir o completo (opção com "remunerações").'.freeze
  VISAO = { provider: 'anthropic', model: 'claude-haiku-5-5' }.freeze
  # tipos que a API da Anthropic aceita; imagem até 5 MB em base64 (~3,75 MB crus); PDF: pedido até 32 MB
  # já em base64 (~24 MB crus) — 20 MB deixa folga. Acima de 100 páginas a API recusa: ver rescue do ask_llm.
  VISAO_LIMITE = { 'image/jpeg' => 3.75.megabytes, 'image/png' => 3.75.megabytes, 'image/webp' => 3.75.megabytes,
                   'image/gif' => 3.75.megabytes, 'application/pdf' => 20.megabytes }.freeze

  def initialize(message)
    @message = message
  end

  # O que o agente precisa saber do que a IA leu (DocumentacaoFaltanteTool): CNIS resumido enquanto o CNIS seguir pendente.
  def self.alertas(lead)
    return [] if lead.custom_attributes&.dig('doc_alertas', 'cnis_resumido').blank?

    lead.doc_checklist.any? { |doc| doc[:status] != 'recebido' && cnis?(doc[:title]) } ? [ALERTA_CNIS] : []
  end

  def self.cnis?(titulo) = titulo.to_s.match?(/CNIS/i)

  def perform
    lead = @message.account.leads.find_by(conversation_id: @message.conversation_id)
    return if lead.blank? || lead.thesis_id.blank? || attachment.blank?

    itens = pendentes(lead)
    item = itens.presence && escolher(lead, itens)
    destino(lead, item) if item.present?
  end

  private

  def destino(lead, item)
    return gravar_sugestao(lead, item) unless marcar_direto?(lead)
    return alertar_cnis_resumido(lead, item) if @cnis_resumido && self.class.cnis?(item.title.presence || item.content)

    marcar_recebido(lead, item)
  end

  # Lead ganho só ganha sugestão (decisão Eduardo 18/10): lá marcar sobe pro Drive e pode ir pro ADVBOX.
  # Exceção: a etapa Documentos (conduzida, só com a chave ligada), onde a IA marca e avisa quem confere (spec §5).
  def marcar_direto?(lead) = visao? && (lead.won_at.blank? || Ramon::EtapaDeGanho.conduzida?(lead.lead_stage))

  def escolher(lead, itens)
    item_id, @cnis_resumido = ask_llm(lead, itens, attachment)
    item = itens.find { |i| i.id == item_id }
    if item.blank?
      Rails.logger.info("[Ramon::DocMatchService] item fora do checklist pendente ou nulo, item_id=#{item_id.inspect}, message=#{@message.id}")
    end
    item
  end

  def attachment
    @attachment ||= @message.attachments.detect { |a| %w[image file].include?(a.file_type) }
  end

  def pendentes(lead)
    status = lead.custom_attributes&.dig('doc_status') || {}
    lead.thesis.thesis_items.where(section: 'documento').reject { |i| status[i.id.to_s] == 'recebido' }
  end

  def ask_llm(lead, itens, attachment)
    result = Ramon::LlmClient.complete(
      **(visao? ? VISAO : Ramon::LlmEscolha.para(lead.account, 'copiloto')),
      system: system_prompt, user: prompt_usuario(lead, itens, attachment), anexo: (attachment.file if visao?),
      funcao: 'doc_match', account_id: lead.account_id, lead_id: lead.id, conversation_id: lead.conversation_id
    )
    parse_resposta(result.content)
  rescue RubyLLM::Error => e
    # Visão recusou o arquivo (PDF com +100 páginas etc.): cai na sugestão sem visão, nunca morre sem deixar nada.
    raise unless visao?

    Rails.logger.warn("[Ramon::DocMatchService] visão recusou o anexo (#{e.message}); seguindo sem visão, message=#{@message.id}")
    @visao = false
    retry
  end

  def system_prompt = Ramon::EtapaDeGanho.documentos_ligado? ? "#{SYSTEM_PROMPT}#{PROMPT_CNIS}" : SYSTEM_PROMPT

  def visao?
    return @visao if defined?(@visao)

    limite = VISAO_LIMITE[attachment.file.content_type]
    @visao = limite.present? && attachment.file.byte_size <= limite && Ramon::LlmEscolha.chave?('anthropic')
  end

  def prompt_usuario(lead, itens, attachment)
    checklist = itens.map { |i| "#{i.id}: #{i.title.presence || i.content}" }.join("\n")
    filename = Ramon::Pseudonymizer.mask(attachment.file.filename.to_s, names: [lead.contact&.name].compact)
    arquivo = "arquivo: #{filename} (#{attachment.file.content_type})"
    conversa = Ramon::Pseudonymizer.mask(transcript(lead), names: [lead.contact&.name].compact)
    "Checklist:\n#{checklist}\n\n#{arquivo}\n\nFim da conversa:\n#{conversa}"
  end

  # DeepSeek roda sem json_schema — nada garante item_id numérico no wire (hábito
  # comum de LLM é devolver "42" string). Integer(..., exception: false) aceita
  # ambos e descarta silenciosamente qualquer outra coisa (null incluso) como nil.
  # @return [Array(Integer|nil, Boolean)] item_id e o sinal cnis_resumido (só conta com a chave ligada)
  def parse_resposta(content)
    parsed = JSON.parse(content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    return [nil, false] unless parsed.is_a?(Hash)

    [Integer(parsed['item_id'].to_s, exception: false), parsed['cnis_resumido'] == true && Ramon::EtapaDeGanho.documentos_ligado?]
  rescue JSON::ParserError
    Rails.logger.warn("[Ramon::DocMatchService] resposta não-JSON do LLM para message=#{@message.id}")
    [nil, false]
  end

  def transcript(lead)
    lead.conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
        .order(:created_at).last(10)
        .filter_map { |m| m.content_for_llm.presence }
        .reject { |t| t == '[Attachment]' }.join("\n")
  end

  # Haiku VIU o arquivo → marca direto (decisão Eduardo 17/10): o mesmo que o
  # "Confirmar" grava (useDocSugestao); desfazer = desmarcar na aba Documentos.
  def marcar_recebido(lead, item)
    gravar(lead, item, 'doc_status' => { item.id.to_s => 'recebido' }, 'doc_anexos' => { item.id.to_s => attachment.id })
    avisar_conferencia(lead, item) if lead.won_at.present? # só a etapa Documentos marca lead ganho (marcar_direto?)
  end

  # Em Documentos, quem conduz confere o que a IA marcou (spec §5); desfazer = desmarcar na aba Documentos.
  # O push vai pelo ntfy público: só a tese, nunca o nome (Ramon::NtfyPushJob.rotulo).
  def avisar_conferencia(lead, item)
    responsavel = Ramon::Documentos::Responsavel.de(lead)
    Ramon::AvisoDaIa.avisar(lead, "IA marcou #{item.title.presence || item.content} de #{lead.name}: verificar",
                            "IA marcou documento (#{Ramon::NtfyPushJob.rotulo(lead)})", 'Confira na aba Documentos do lead',
                            user_ids: [responsavel&.id].compact)
  end

  # CNIS resumido não serve (spec §3): nada marcado; o alerta faz o agente pedir o completo (DocumentacaoFaltanteTool).
  def alertar_cnis_resumido(lead, item)
    lead.reload
    lead.update!(custom_attributes: lead.custom_attributes.to_h.deep_merge('doc_alertas' => { 'cnis_resumido' => Time.zone.now.iso8601 }))
    Ramon::EventoInline.registrar(
      @message.conversation, '✦ IA do hub leu o anexo: é o CNIS resumido, que não serve — não marcado; pedir o completo (com remunerações).',
      tipo: 'doc_match', extra: { 'item_id' => item.id, 'attachment_id' => attachment.id, 'lead_id' => lead.id }
    )
  end

  # Sem visão (só nome + conversa) é chute demais pra marcar: fica a sugestão.
  def gravar_sugestao(lead, item)
    gravar(lead, item, 'doc_sugestao' => { 'item_id' => item.id, 'attachment_id' => attachment.id,
                                           'message_id' => @message.id, 'em' => Time.zone.now.iso8601,
                                           'resolvida' => false })
  end

  def gravar(lead, item, patch)
    lead.reload # padrão advbox: merge sobre o estado atual, só a chave nova
    lead.update!(custom_attributes: lead.custom_attributes.to_h.deep_merge(patch))
    titulo = item.title.presence || item.content
    Ramon::EventoInline.registrar(
      @message.conversation,
      if patch.key?('doc_status')
        "✦ IA do hub leu o anexo: é \"#{titulo}\" — já marcado como recebido na aba Documentos."
      else
        "✦ IA do hub sugeriu #{visao? ? 'lendo o anexo' : 'pelo nome do arquivo'}: é \"#{titulo}\" — confirme aqui ou na aba Documentos."
      end,
      tipo: 'doc_match',
      extra: { 'item_id' => item.id, 'attachment_id' => attachment.id, 'lead_id' => lead.id }
    )
    Ramon::Fluxos::Disparo.externo('documento_recebido', lead, 'documento' => titulo)
  end
end
