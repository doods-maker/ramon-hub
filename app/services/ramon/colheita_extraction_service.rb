# Extração estruturada da colheita da reunião (artefato 2 da colheita
# aprovada em 15/07/2026) a partir do transcript da conversa — roda após
# cada transcrição de áudio do Whisper. Preenche lead.custom_attributes['colheita']
# (dados + lacunas) e dcb_em quando ainda vazio (relógio de prescrição).
class Ramon::ColheitaExtractionService
  # ponytail: schema aprovado só p/ auxílio-acidente; schema por tese quando houver outra colheita aprovada.
  THESIS_MATCH = /auxílio-acidente/i
  MAX_MESSAGES = 200
  AUXILIO_DOENCA = %w[B31 B91].freeze

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
      "lacunas": [{"campo": "caminho.do.campo", "como_obter": "documento/fonte que resolve"}]
    }
    Regras invioláveis:
    - NUNCA invente um dado. Campo não mencionado na conversa = null (ou lista vazia) + entrada em "lacunas".
    - Datas no formato YYYY-MM-DD. acidente.tipo em [trabalho, trajeto, outra_natureza];
      cat_emitida em [sim, nao, nao_sabe]; sequela.consolidada em [sim, em_tratamento, nao_sabe].
    - Valor dito de forma incerta na fala: preencha e liste o caminho do campo em "confirmar".
    - Tokens de máscara ([cpf], [telefone], [endereco], [email], [cep], [nome]) significam dado protegido: deixe o campo null e registre em "lacunas" com como_obter "confirmar no cadastro/documento".
    - "profissao" é a atividade habitual; "sequela.limitacao_concreta" é como a sequela reduz esse trabalho, em fatos.
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
    text = "Tese: #{@lead.thesis.name}\n\n#{transcript}"
    text = Ramon::Pseudonymizer.mask(text, names: [@lead.name, @lead.contact&.name]) unless sensitive_ok?
    Ramon::LlmClient.complete(provider: provider, model: model,
                              system: SYSTEM_PROMPT, user: text, sensitive: sensitive_ok?)
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

    obj
  rescue JSON::ParserError
    raise ArgumentError, 'JSON da colheita inválido.'
  end

  def write_back(dados)
    attrs = {
      custom_attributes: (@lead.custom_attributes || {}).merge('colheita' => colheita_payload(dados))
    }
    dcb = extracted_dcb(dados)
    attrs[:dcb_em] = dcb if dcb && @lead.dcb_em.blank?
    @lead.update!(attrs)
  end

  def colheita_payload(dados)
    {
      'dados' => dados.except('lacunas', 'confirmar'),
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
