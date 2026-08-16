# Modo do copiloto POR CONVERSA (Onda C, spec D5). Fonte única da leitura:
# custom_attributes['copiloto_modo'], default rascunho — piloto é opt-in
# explícito por conversa (decisão Eduardo 14/08).
module Ramon::CopilotoModo
  MODOS = %w[manual rascunho piloto_limitado piloto_total].freeze
  DEFAULT = 'rascunho'.freeze

  module_function

  def of(conversation)
    modo = conversation&.custom_attributes&.[]('copiloto_modo').to_s
    MODOS.include?(modo) ? modo : DEFAULT
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
