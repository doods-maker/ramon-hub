# Modo do copiloto POR CONVERSA (Onda C, spec D5). Fonte única da leitura:
# custom_attributes['copiloto_modo'], default = RAMON_COPILOTO_MODO_DEFAULT,
# rascunho se vazia — piloto é opt-in explícito por conversa (decisão Eduardo 14/08).
module Ramon::CopilotoModo
  MODOS = %w[manual rascunho piloto_limitado piloto_total].freeze
  DEFAULT = 'rascunho'.freeze

  module_function

  # D7: piloto_limitado vira padrao por env depois de ~20 conversas revisadas.
  # ponytail: a env vale pra TODA conversa sem atributo (antigas inclusive) — antes de virar,
  # carimbar copiloto_modo=rascunho nas abertas antigas pelo console.
  def default
    env = ENV.fetch('RAMON_COPILOTO_MODO_DEFAULT', DEFAULT).to_s.strip
    MODOS.include?(env) ? env : DEFAULT
  end

  def of(conversation)
    modo = conversation&.custom_attributes&.[]('copiloto_modo').to_s
    MODOS.include?(modo) ? modo : default
  end

  def piloto?(modo)
    modo.start_with?('piloto_')
  end

  # Handoff é logística por definição (constraint global) — nunca vira rascunho
  # em piloto_limitado. logistica_ok nil (não classificado) é fail-safe: rascunho.
  def envia?(modo, handoff:, logistica_ok:)
    piloto?(modo) && (handoff || modo != 'piloto_limitado' || logistica_ok == true)
  end

  def carimbo(modo)
    { 'ramon_piloto' => { 'modo' => modo, 'em' => Time.zone.now.iso8601 } }
  end
end
