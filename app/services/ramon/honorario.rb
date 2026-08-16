# Fórmula do honorário da tese: percentual × atrasados + N × mensalidades.
# Único lugar da regra — usada pelo simulador (LeadSimulacoesController) e pela
# tool simular_honorario do agente. Devolve o mesmo Hash do endpoint.
class Ramon::Honorario
  SEM_CONFIG = 'tese do lead sem honorário configurado (% e nº de mensalidades)'.freeze

  def self.calcular(tese, atrasados:, mensal:)
    configurada = tese && (tese.honorario_percentual.present? || tese.honorario_n_mensalidades.present?)
    return { valor: nil, motivo: SEM_CONFIG } unless configurada

    percentual = tese.honorario_percentual || 0
    n_mensalidades = tese.honorario_n_mensalidades || 0
    valor = (BigDecimal(atrasados.to_s) * percentual / 100) + (BigDecimal(mensal.to_s) * n_mensalidades)
    { valor: format('%.2f', valor), percentual: percentual.to_f, n_mensalidades: n_mensalidades, tese: tese.name }
  end
end
