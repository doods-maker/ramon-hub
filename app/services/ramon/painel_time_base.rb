# Base dos KPIs do Painel do time (Ramon::PainelTimeSdr / PainelTimeCloser):
# cada KPI devolve { valor, num, den } — a tela mostra "11 de 21". `ids` são as
# pessoas somadas (1 = a pessoa; todas = o time); `periodo` é um Range de Time.
class Ramon::PainelTimeBase
  TIME_ZONE = Ramon::ExtratoVariavel::TIME_ZONE

  pattr_initialize [:account!, :ids!, :periodo!]

  private

  def leads
    account.leads.funil.reorder(nil)
  end

  def atividades(kind)
    LeadActivity.unscoped.where(account_id: account.id, kind: kind)
  end

  # % com 1 casa; sem denominador = sem dado (nil), nunca 0%.
  def taxa(num, den)
    { valor: den.positive? ? (100.0 * num / den).round(1) : nil, num: num, den: den }
  end

  def mediana(lista)
    return nil if lista.empty?

    ordenada = lista.sort
    meio = ordenada.size / 2
    (ordenada.size.odd? ? ordenada[meio] : (ordenada[meio - 1] + ordenada[meio]) / 2.0).round(1)
  end

  # { Date => n } do groupdate (já com os zeros do período) → série da tela.
  def serie(contagens)
    { total: contagens.values.sum, serie: contagens.map { |inicio, quantos| { inicio: inicio.iso8601, n: quantos } } }
  end
end
