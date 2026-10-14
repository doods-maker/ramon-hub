# Modo do copiloto POR CONVERSA (Onda C, spec D5; F3 do roteiro da tese). Fonte única da leitura:
# custom_attributes['copiloto_modo'] → padrão da caixa (inboxes.ramon_copiloto_modo) → RAMON_COPILOTO_MODO_DEFAULT →
# rascunho. Piloto é opt-in explícito (decisão Eduardo 14/08). Mora em app/ desde a F3: o motor do roteiro e o limite
# dos modos "sozinha até…" usam, e o CI testa.
module Ramon::CopilotoModo
  # "Sozinha até…" (spec roteiro §3.7): envia direto como o piloto total até o limite (Ramon::CopilotoLimite).
  LIMITES = { 'piloto_ate_qualificacao' => 'qualificacao', 'piloto_ate_reuniao' => 'reuniao',
              'piloto_ate_contrato' => 'contrato' }.freeze
  MODOS = (%w[manual rascunho piloto_limitado piloto_total] + LIMITES.keys).freeze
  DEFAULT = 'rascunho'.freeze

  module_function

  # D7: piloto_limitado vira padrao por env depois de ~20 conversas revisadas.
  # ponytail: a env e o padrão da caixa valem pra TODA conversa sem atributo (antigas inclusive) — antes de virar,
  # carimbar copiloto_modo=rascunho nas abertas antigas pelo console.
  def default(inbox = nil)
    caixa = inbox&.ramon_copiloto_modo
    return caixa if MODOS.include?(caixa)

    env = ENV.fetch('RAMON_COPILOTO_MODO_DEFAULT', DEFAULT).strip
    MODOS.include?(env) ? env : DEFAULT
  end

  def of(conversation)
    modo = conversation&.custom_attributes&.[]('copiloto_modo').to_s
    MODOS.include?(modo) ? modo : default(conversation&.inbox)
  end

  def piloto?(modo)
    modo.start_with?('piloto_')
  end

  # Etapa e Perdido do roteiro aplicados direto (decisões 13/10): piloto total e os modos "sozinha até…".
  def direto?(modo)
    modo == 'piloto_total' || LIMITES.key?(modo)
  end

  # Handoff é logística por definição (constraint global) — nunca vira rascunho
  # em piloto_limitado. logistica_ok nil (não classificado) é fail-safe: rascunho.
  def envia?(modo, handoff:, logistica_ok:)
    piloto?(modo) && (handoff || modo != 'piloto_limitado' || logistica_ok == true)
  end

  def carimbo(modo)
    { 'ramon_piloto' => { 'modo' => modo, 'em' => Time.zone.now.iso8601 } }
  end

  # Conversa nova numa caixa com modo padrão: grava o modo na conversa — o seletor e o "Pausar" do front leem o
  # atributo. Atributo já presente (escolhido antes de o ouvinte rodar) vence.
  def carimbar_padrao(conversation)
    modo = conversation.inbox&.ramon_copiloto_modo
    attrs = conversation.custom_attributes || {}
    return if modo.blank? || attrs.key?('copiloto_modo')

    conversation.update!(custom_attributes: attrs.merge('copiloto_modo' => modo))
  end
end
