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
end
