class Leads::KitService
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você transforma uma análise jurídica de viabilidade em um "Kit do Closer": material em linguagem simples para um vendedor SEM formação jurídica usar numa conversa de WhatsApp com o cliente.

    Responda APENAS com um objeto JSON válido (sem texto fora do JSON, sem cercas de código), nesta forma exata:
    {
      "resumo_leigo": "3-4 linhas, sem juridiquês, do que se trata e por que vale a pena",
      "roteiro_perguntas": ["pergunta 1 exata pro WhatsApp", "pergunta 2"],
      "documentos": [{"documento": "nome", "porque": "motivo curto"}],
      "venda_objecoes": {"pitch": "como explicar a viabilidade em linguagem de venda", "objecoes": [{"objecao": "...", "resposta": "..."}]},
      "proximo_passo": "frase curta de fechamento: assinar contrato e agendar reunião com o jurídico"
    }
    Não invente fatos fora da análise. Português do Brasil.
  PROMPT

  def initialize(triage)
    @triage = triage
    @lead = triage.lead
    @agent = triage.triage_agent
  end

  def perform
    @triage.update!(kit_status: 'running')
    result = call_llm
    @triage.update!(kit: parse_kit(result.content), kit_status: 'ready')
    record_usage(result)
  rescue StandardError => e
    mark_error(e)
  end

  private

  def mark_error(error)
    @triage.update!(kit_status: 'error', kit: { 'error' => error.message.truncate(500) })
  rescue StandardError => e
    Rails.logger.error("KitService: falha ao gravar erro do kit da triage #{@triage.id}: #{e.message}")
  end

  # ponytail: record_usage duplicado nos 2 services; extrair concern se surgir um 3º consumidor.
  def record_usage(result)
    @triage.increment!(:input_tokens, result.input_tokens.to_i)
    @triage.increment!(:output_tokens, result.output_tokens.to_i)
  end

  def call_llm
    Ramon::LlmClient.complete(provider: @agent.provider, model: @agent.model,
                              system: SYSTEM_PROMPT, user: user_prompt,
                              sensitive: @agent.sensitive)
  end

  def user_prompt
    parts = [
      "Cliente: #{@lead.name}",
      @agent.area.present? ? "Área: #{@agent.area}" : nil,
      "Viabilidade apurada: #{@triage.viability.presence || 'não informada'}",
      '',
      'Análise jurídica da triagem:',
      @triage.result,
      prescription_prompt_line
    ]
    text = parts.compact.join("\n")
    Ramon::Pseudonymizer.mask(text, names: [@lead.name, @lead.contact&.name])
  end

  def prescription_prompt_line
    presc = @lead.prescription
    return if presc.nil?

    bleeding = presc[:lost_installments].positive?
    monthly = @lead.benefit_monthly_value
    "Prescricao (Art. 103 par. unico, Lei 8.213/91): DCB em #{I18n.l(@lead.dcb_em)}, " \
      "#{presc[:months_since_dcb]} meses atras. #{presc[:lost_installments]} parcelas ja prescritas" \
      "#{bleeding && presc[:lost_value] ? " (~R$ #{presc[:lost_value].to_i})" : ''}." \
      "#{bleeding && monthly.present? ? " A cada mes sem acao, mais R$ #{monthly.to_i} prescrevem." : ''}"
  end

  # Porta o parse tolerante de lib/kit-closer.ts: aceita cercas ```json e
  # texto em volta; valida resumo_leigo; coage arrays/strings item a item.
  def parse_kit(raw)
    body = raw.to_s.gsub(/```json/i, '').gsub('```', '')
    ini = body.index('{')
    fim = body.rindex('}')
    raise ArgumentError, 'Resposta da IA não contém JSON do kit.' if ini.nil? || fim.nil? || fim <= ini

    obj = JSON.parse(body[ini..fim])
    raise ArgumentError, 'Kit sem resumo_leigo.' if obj['resumo_leigo'].to_s.strip.empty?

    normalize(obj)
  rescue JSON::ParserError
    raise ArgumentError, 'JSON do kit inválido.'
  end

  def normalize(obj)
    venda = obj['venda_objecoes'].is_a?(Hash) ? obj['venda_objecoes'] : {}
    {
      'resumo_leigo' => obj['resumo_leigo'].to_s.strip,
      'roteiro_perguntas' => string_list(obj['roteiro_perguntas']),
      'documentos' => pair_list(obj['documentos'], 'documento', 'porque'),
      'venda_objecoes' => {
        'pitch' => venda['pitch'].to_s,
        'objecoes' => pair_list(venda['objecoes'], 'objecao', 'resposta')
      },
      'proximo_passo' => obj['proximo_passo'].to_s.strip
    }
  end

  def string_list(value)
    Array(value).map(&:to_s).reject(&:empty?)
  end

  def pair_list(value, key_field, value_field)
    Array(value).filter_map do |item|
      next unless item.is_a?(Hash)

      pair = { key_field => item[key_field].to_s, value_field => item[value_field].to_s }
      pair[key_field].empty? ? nil : pair
    end
  end
end
