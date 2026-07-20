# Extração estruturada da colheita (artefato 2 da colheita aprovada em
# 15/07/2026) a partir do transcript da conversa — roda após cada transcrição
# de áudio do Whisper e, com debounce, após mensagens de chat do lead.
# Preenche lead.custom_attributes['colheita'] (dados + lacunas), marca 'ia'
# nos itens do checklist já respondidos (colheita_status, sem sobrescrever
# escolha humana), CPF/nascimento vazios do contato (cadastro) e dcb_em
# quando ainda vazio (relógio de prescrição).
class Ramon::ColheitaExtractionService
  # ponytail: schema aprovado só p/ auxílio-acidente; schema por tese quando houver outra colheita aprovada.
  THESIS_MATCH = /auxílio-acidente/i
  MAX_MESSAGES = 200
  AUXILIO_DOENCA = %w[B31 B91].freeze
  SCHEMA_SECTIONS = %w[cliente qualificacao acidente sequela beneficios fechamento].freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você extrai dados estruturados da conversa entre a equipe de um escritório previdenciário e um cliente com possível caso de auxílio-acidente.
    Responda APENAS com um objeto JSON válido (sem texto fora do JSON, sem cercas de código), nesta forma exata:
    {
      "cliente": {"nome_completo": null, "cpf": null, "rg": null, "nascimento": null, "estado_civil": null,
                  "profissao": null, "endereco": null, "whatsapp": null, "renda_aproximada": null},
      "qualificacao": {"aposentado": null, "qualidade_segurado_epoca": null,
                       "qualidade_segurado_como": null, "recebeu_auxilio_doenca": null},
      "acidente": {"data": null, "tipo": null, "descricao": null, "cat_emitida": null, "empregador_na_epoca": null},
      "sequela": {"descricao": null, "cid": null, "consolidada": null, "limitacao_concreta": null, "tratamentos": []},
      "beneficios": [{"nb": null, "especie": "B31|B91|B94|outro", "dib": null, "dcb": null,
                      "situacao": "cessado|ativo|indeferido|nao_requerido", "motivo": null}],
      "fechamento": {"honorario_apresentado": null, "simulacao_mostrada": null, "contrato_assinado": null,
                     "motivo_nao_assinatura": null, "objecoes": [], "sensibilidades": null},
      "confirmar": ["caminho.do.campo dito de forma incerta"],
      "lacunas": [{"campo": "caminho.do.campo", "como_obter": "documento/fonte que resolve"}],
      "checklist_ok": [123]
    }
    Regras invioláveis:
    - NUNCA invente um dado. Campo não mencionado na conversa = null (ou lista vazia) + entrada em "lacunas".
    - Datas no formato YYYY-MM-DD. acidente.tipo em [trabalho, trajeto, outra_natureza];
      cat_emitida em [sim, nao, nao_sabe]; sequela.consolidada em [sim, em_tratamento, nao_sabe].
    - Valor dito de forma incerta na fala: preencha e liste o caminho do campo em "confirmar".
    - Tokens de máscara ([cpf], [rg], [telefone], [endereco], [email], [cep], [nome]) significam dado protegido: deixe o campo null e registre em "lacunas" com como_obter "confirmar no cadastro/documento".
    - "profissao" é a atividade habitual; "sequela.limitacao_concreta" é como a sequela reduz esse trabalho, em fatos.
    - "checklist_ok": ids (números) dos itens do checklist listados na entrada que a conversa JÁ responde com clareza; na dúvida, NÃO inclua o item.
    Português do Brasil.
  PROMPT

  def initialize(lead)
    @lead = lead
  end

  def perform
    return unless extractable?

    transcript = conversation_transcript
    return if transcript.blank?

    result = call_llm(transcript)
    write_back(parse(result.content))
  rescue Ramon::LlmClient::TransientError
    raise
  rescue StandardError => e
    Rails.logger.error("ColheitaExtraction: falha no lead #{@lead.id}: #{e.message}")
  end

  private

  def extractable?
    @lead.thesis&.name&.match?(THESIS_MATCH) && @lead.conversation.present?
  end

  def provider
    ENV.fetch('RAMON_COLHEITA_PROVIDER', 'deepseek')
  end

  def model
    ENV.fetch('RAMON_COLHEITA_MODEL', 'deepseek-chat')
  end

  # Com provider autorizado p/ dado sensível (anthropic/openai) o transcript vai
  # íntegro e a extração cobre identificação civil; senão (deepseek, padrão) vai
  # pseudonimizado (LGPD) — PII mascarada vira lacuna, datas/valores extraem normal.
  def sensitive_ok?
    Ramon::LlmClient::SENSITIVE_OK_PROVIDERS.include?(provider)
  end

  def call_llm(transcript)
    text = "Tese: #{@lead.thesis.name}\n\n#{checklist_block}#{transcript}"
    text = Ramon::Pseudonymizer.mask(text, names: [@lead.name, @lead.contact&.name]) unless sensitive_ok?
    Ramon::LlmClient.complete(provider: provider, model: model,
                              system: SYSTEM_PROMPT, user: text, sensitive: sensitive_ok?)
  end

  def checklist_items
    @checklist_items ||= @lead.thesis.thesis_items.where(section: 'colheita')
  end

  def checklist_block
    return '' if checklist_items.empty?

    lines = checklist_items.map { |item| "#{item.id}: #{item.title.presence || item.content}" }
    "Itens do checklist da colheita (id: item):\n#{lines.join("\n")}\n\n"
  end

  def conversation_transcript
    messages = @lead.conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                    .order(:created_at).last(MAX_MESSAGES)
    lines = messages.filter_map do |m|
      text = m.content_for_llm
      next if text.blank?
      next if text == '[Attachment]'

      "#{m.incoming? ? 'Cliente' : 'Atendimento'}: #{text}"
    end
    return nil if lines.empty?

    "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end

  # Mesmo parse tolerante do Leads::KitService: aceita cercas ```json e texto em volta.
  def parse(raw)
    body = raw.to_s.gsub(/```json/i, '').gsub('```', '')
    ini = body.index('{')
    fim = body.rindex('}')
    raise ArgumentError, 'Resposta da IA não contém JSON da colheita.' if ini.nil? || fim.nil? || fim <= ini

    obj = JSON.parse(body[ini..fim])
    raise ArgumentError, 'Colheita sem objeto raiz.' unless obj.is_a?(Hash)
    # JSON válido mas fora do schema (LLM divagou) não pode sobrescrever colheita boa.
    raise ArgumentError, 'JSON fora do schema da colheita.' unless obj.keys.intersect?(SCHEMA_SECTIONS)

    obj
  rescue JSON::ParserError
    raise ArgumentError, 'JSON da colheita inválido.'
  end

  # A chamada de LLM demora — reload antes do merge, senão o snapshot velho
  # reverte o que painel/ZapSign/AdvBox gravaram nesse meio-tempo (e o guard
  # do dcb_em avaliaria dado obsoleto, sobrescrevendo valor humano).
  def write_back(dados)
    @lead.reload
    fill_contact_blanks(dados['cliente'])
    attrs = { custom_attributes: merged_custom_attributes(dados) }
    dcb = extracted_dcb(dados)
    attrs[:dcb_em] = dcb if dcb && @lead.dcb_em.blank?
    @lead.update!(attrs)
  end

  # Cadastro: CPF e nascimento têm coluna própria no contato (Linha da Vida,
  # ZapSign) — a extração preenche SÓ campo vazio; dado humano nunca é tocado.
  # Roda antes do update! do lead pro broadcast já sair com o contato novo.
  def fill_contact_blanks(cliente)
    contact = @lead.contact
    return if contact.blank? || !cliente.is_a?(Hash)

    updates = contact_updates(contact, cliente)
    return if updates.empty?
    return if contact.update(updates)

    # CPF inválido/duplicado não pode derrubar a colheita: tenta sem ele.
    updates.delete(:cpf)
    contact.reload.update(updates) if updates.any?
  end

  def contact_updates(contact, cliente)
    updates = {}
    cpf = cliente['cpf'].to_s.gsub(/\D/, '')
    updates[:cpf] = cpf if contact.cpf.blank? && cpf.present?
    nascimento = parse_date(cliente['nascimento'])
    updates[:data_nascimento] = nascimento if contact.data_nascimento.blank? && nascimento
    updates
  end

  def merged_custom_attributes(dados)
    merged = (@lead.custom_attributes || {}).merge('colheita' => colheita_payload(dados))
    status = checklist_status_with_ai(dados, merged['colheita_status'] || {})
    merged['colheita_status'] = status if status
    merged
  end

  # Itens do checklist que a conversa já responde ganham 'ia' — mas SÓ em chave
  # que o humano nunca tocou: true (marcou) e false (desmarcou = veto) são dele.
  def checklist_status_with_ai(dados, current)
    valid_ids = checklist_items.map { |item| item.id.to_s }
    additions = (Array(dados['checklist_ok']).map(&:to_s) & valid_ids).reject { |id| current.key?(id) }
    return nil if additions.empty?

    current.merge(additions.index_with { 'ia' })
  end

  def colheita_payload(dados)
    {
      'dados' => dados.except('lacunas', 'confirmar', 'checklist_ok'),
      'lacunas' => lacuna_list(dados['lacunas']),
      'confirmar' => Array(dados['confirmar']).map(&:to_s).reject(&:empty?),
      'extraida_em' => Time.zone.now.iso8601,
      'mascarada' => !sensitive_ok?
    }
  end

  def lacuna_list(value)
    Array(value).filter_map do |item|
      next unless item.is_a?(Hash)

      campo = item['campo'].to_s
      campo.empty? ? nil : { 'campo' => campo, 'como_obter' => item['como_obter'].to_s }
    end
  end

  # DCB do auxílio-doença cessado mais recente = termo inicial do auxílio-acidente
  # (Tema 862/STJ) → alimenta o relógio de prescrição. Nunca sobrescreve dado humano.
  def extracted_dcb(dados)
    Array(dados['beneficios']).filter_map do |b|
      next unless b.is_a?(Hash)
      next unless AUXILIO_DOENCA.include?(b['especie'].to_s.upcase)
      next unless b['situacao'].to_s == 'cessado'

      parse_date(b['dcb'])
    end.max
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
