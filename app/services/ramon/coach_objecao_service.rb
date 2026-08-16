# Coach de objeção em tempo real (Onda D, spec D4): mensagem incoming com
# texto → LLM decide se há objeção e monta 2 linhas de resposta a partir do
# playbook da tese (thesis_items section 'objecao'). O resultado vira evento
# inline na conversa ("Usar →" só INSERE no editor — princípio de aprovação).
# Fail-safe: qualquer erro = silêncio. Gap mínimo de 10 min por conversa.
class Ramon::CoachObjecaoService
  PROVIDER = 'deepseek'.freeze
  GAP_MINUTOS = 10
  MIN_CHARS = 20

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é coach de fechamento de um escritório previdenciário. Recebe a última mensagem de um
    cliente e o playbook de objeções da tese. Se a mensagem contiver uma OBJEÇÃO (custo,
    desconfiança, tempo, "vou pensar", medo de perder), monte exatamente 2 opções de resposta
    curtas (estilo WhatsApp, 2-3 frases), seguindo a receita: concordar → amenizar → contornar →
    avançar. Use os argumentos do playbook quando servirem.
    Regras obrigatórias: NUNCA prometa resultado do caso, valor ou prazo do INSS (regra da OAB).
    Responda APENAS JSON válido (sem markdown):
    {"objecao": "<rótulo curto>", "opcoes": [{"titulo": "...", "texto": "..."}, {"titulo": "...", "texto": "..."}]}
    ou {"objecao": "nenhuma"} se não houver objeção. Na dúvida, "nenhuma".
  PROMPT

  def initialize(message, lead)
    @message = message
    @lead = lead
  end

  def perform
    return unless elegivel?

    parsed = ask_llm
    marcar_ultima_em
    processar(parsed)
  rescue StandardError => e
    Rails.logger.warn("[Ramon::CoachObjecaoService] silêncio (#{e.class}: #{e.message}) message=#{@message.id}")
  end

  private

  def elegivel?
    @message.content.to_s.strip.length >= MIN_CHARS && !recente? && playbook.present?
  end

  def processar(parsed)
    return if parsed.blank? || parsed['objecao'].blank? || parsed['objecao'] == 'nenhuma'

    opcoes = normalizar_opcoes(parsed)
    return if opcoes.empty?

    registrar_evento(parsed['objecao'].to_s, opcoes)
  end

  def normalizar_opcoes(parsed)
    Array(parsed['opcoes']).first(2).filter_map do |o|
      next if o['texto'].blank?

      { 'titulo' => o['titulo'].to_s.presence || 'Opção', 'texto' => o['texto'].to_s }
    end
  end

  def recente?
    ultima = @lead.custom_attributes.dig('coach', 'ultima_em')
    ultima.present? && Time.zone.parse(ultima.to_s) > GAP_MINUTOS.minutes.ago
  rescue ArgumentError
    false
  end

  def playbook
    @playbook ||= @lead.thesis.thesis_items.where(section: 'objecao').map { |i| "- #{i.title}: #{i.content}" }.join("\n")
  end

  def ask_llm
    texto = Ramon::Pseudonymizer.mask(@message.content.to_s, names: [@lead.name, @lead.contact&.name].compact)
    result = Ramon::LlmClient.complete(
      provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT,
      user: "Playbook de objeções:\n#{playbook}\n\nMensagem do cliente:\n#{texto}"
    )
    parsed = JSON.parse(result.content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    Rails.logger.debug { "[Ramon::CoachObjecaoService] parse nil message=#{@message.id}" }
    nil
  end

  def registrar_evento(objecao, opcoes)
    Ramon::EventoInline.registrar(
      @message.conversation,
      "⚡ Coach do hub: objeção detectada (#{objecao}) — 2 respostas prontas do playbook.",
      tipo: 'coach',
      extra: { 'objecao' => objecao, 'opcoes' => opcoes }
    )
  end

  # lição lost update: reload + merge só da chave coach
  def marcar_ultima_em
    @lead.reload
    @lead.update!(custom_attributes: @lead.custom_attributes.to_h.merge(
      'coach' => { 'ultima_em' => Time.zone.now.iso8601 }
    ))
  end
end
