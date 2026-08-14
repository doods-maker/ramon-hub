# Valor Estimado (CONTEXT.md): honorário previsto pela regra da Tese, automático
# desde a qualificação; ajuste manual SEMPRE vence; no ganho o valor é contrato
# e o automático nunca mais toca. Roda em before_save: mesmo UPDATE, sem loop.
#
# Ordem de callback: incluído no Lead DEPOIS de `track_stage_cycle` — este
# `before_save` lê `won_at`, e é o `track_stage_cycle` quem grava `won_at` a
# partir da etapa (ver `apply_stage_timestamps`). Um único save que ganha o
# lead e mexe no valor precisa ver o `won_at` já fresco.
module LeadValorEstimado
  extend ActiveSupport::Concern

  included do
    before_save :recalcular_valor_estimado
  end

  private

  def recalcular_valor_estimado
    return if won_at.present? || valor_manual?

    estimado, base = estimativa
    return if estimado.blank? || estimado.zero?
    return if value.present? && value.to_d == estimado.to_d

    self.value = estimado
    self.custom_attributes = custom_attributes.to_h.merge(
      'valor_estimado' => { 'origem' => 'auto', 'base' => base, 'em' => Time.zone.now.iso8601 }
    )
  end

  def valor_manual?
    origem = custom_attributes&.dig('valor_estimado', 'origem')
    return origem == 'manual' if origem.present?

    value.present? # legado: valor preenchido antes da flag existir = mão humana
  end

  def estimativa
    simulado = custom_attributes&.dig('ultima_simulacao', 'honorario_valor')
    return [BigDecimal(simulado.to_s), 'simulacao'] if simulado.present? && simulado.to_f.positive?

    n = thesis&.honorario_n_mensalidades
    return [nil, nil] if n.blank? || n.zero? || benefit_monthly_value.blank?

    [benefit_monthly_value * n, 'mensalidades']
  end
end
