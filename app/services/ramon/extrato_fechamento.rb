# Fechamento do extrato da variável (regulamento §6): no 3º dia útil depois do
# fim do mês a apuração vira definitiva — o extrato de cada pessoa é guardado
# (ExtratoFechado) e a tela passa a mostrar o guardado, sem recalcular (troca de
# dono, reunião ou carimbo depois disso não mexe no mês fechado).
# Fecha no job diário (Ramon::ExtratoFechamentoJob) ou na 1ª leitura depois da
# data, o que vier primeiro.
# ponytail: dia útil = segunda a sexta, sem feriados; tabela de feriados se o
# escritório pedir.
module Ramon::ExtratoFechamento
  DIAS_UTEIS = 3

  module_function

  def data_de_fechamento(mes)
    (mes.beginning_of_month.next_month..).lazy.select(&:on_weekday?).first(DIAS_UTEIS).last
  end

  def hoje
    Time.current.in_time_zone(Ramon::ExtratoVariavel::TIME_ZONE).to_date
  end

  def fechado?(mes)
    hoje >= data_de_fechamento(mes)
  end

  # Extrato do mês: aberto = ao vivo; fechado = o guardado.
  def pessoas(account, mes)
    return Ramon::ExtratoVariavel.new(account: account, mes: mes).pessoas unless fechado?(mes)

    fechar!(account, mes)
    ExtratoFechado.where(account: account, competencia: mes).order(:id)
                  .map { |registro| registro.payload.deep_symbolize_keys.merge(fechado_em: registro.fechado_em.iso8601) }
  end

  # Idempotente: mês já guardado não é recalculado (nem com gente nova no time).
  def fechar!(account, mes)
    return if ExtratoFechado.exists?(account: account, competencia: mes)

    agora = Time.current
    ExtratoFechado.transaction do
      Ramon::ExtratoVariavel.new(account: account, mes: mes).pessoas.each do |linha|
        ExtratoFechado.create!(account: account, user_id: linha[:user][:id], papel: linha[:papel],
                               competencia: mes, payload: linha, fechado_em: agora)
      end
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil # outra leitura (ou o job) fechou o mesmo mês ao mesmo tempo
  end
end
