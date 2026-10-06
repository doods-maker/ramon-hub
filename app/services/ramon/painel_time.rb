# Painel do time (operação comercial, doc 04 §3–§4): KPIs do SDR e do Closer
# com valor, numerador/denominador e a meta do plano; meta do mês × realizado;
# série de volume. Pessoas, mês e meta vêm do Extrato da variável
# (Ramon::ExtratoVariavel) — o realizado é a mesma contagem que paga.
# `user` presente = só a linha dela (agente), sem o agregado do time.
class Ramon::PainelTime
  TIME_ZONE = Ramon::ExtratoVariavel::TIME_ZONE
  PERIODOS = %w[hoje semana mes mes_passado].freeze
  KPIS = { Ramon::Papeis::SDR => Ramon::PainelTimeSdr, Ramon::Papeis::CLOSER => Ramon::PainelTimeCloser }.freeze

  # Metas do plano (doc 04 §4). sentido: min = quanto maior melhor (≥ alvo);
  # max = ≤ alvo. unidade: % | min (1ª resposta) | n (contagem).
  METAS = {
    Ramon::Papeis::SDR => {
      primeira_resposta: { alvo: 5, sentido: 'max', unidade: 'min' },
      sem_resposta: { alvo: 0, sentido: 'max', unidade: 'n' },
      qualificado_agendada: { alvo: 70, sentido: 'min', unidade: '%' },
      show: { alvo: 75, sentido: 'min', unidade: '%' },
      nao_qualificada: { alvo: 15, sentido: 'max', unidade: '%' },
      registro_completo: { alvo: 100, sentido: 'min', unidade: '%' }
    },
    Ramon::Papeis::CLOSER => {
      conversao: { alvo: 50, sentido: 'min', unidade: '%' },
      assinado_na_reuniao: { alvo: 80, sentido: 'min', unidade: '%' },
      docs_7d: { alvo: 80, sentido: 'min', unidade: '%' },
      cancelamento_7d: { alvo: 5, sentido: 'max', unidade: '%' },
      painel: { alvo: 100, sentido: 'min', unidade: '%' },
      dossie_24h: { alvo: 100, sentido: 'min', unidade: '%' },
      vou_pensar_48h: { alvo: 100, sentido: 'min', unidade: '%' }
    }
  }.freeze

  pattr_initialize [:account!, :papel!, :periodo!, :user]

  def perform
    {
      papel: papel, periodo: periodo, inicio: intervalo.begin.iso8601, fim: intervalo.end.iso8601,
      metas: METAS.fetch(papel),
      time: user ? nil : linha(nil, pessoas),
      pessoas: pessoas.map { |pessoa| linha(pessoa[:user], [pessoa]) }
    }
  end

  private

  def pessoas
    @pessoas ||= Ramon::ExtratoVariavel.new(account: account, mes: mes).pessoas.select do |pessoa|
      pessoa[:papel] == papel && (user.nil? || pessoa[:user][:id] == user.id)
    end
  end

  def linha(dono, grupo)
    kpis = KPIS.fetch(papel).new(account: account, ids: grupo.map { |pessoa| pessoa[:user][:id] }, periodo: intervalo)
    { user: dono, meta_mes: meta_mes(grupo).merge(kpis.meta_extra(intervalo_do_mes)), kpis: kpis.kpis, volume: kpis.volume }
  end

  # Meta somada de quem tem meta lançada; realizado = contagem do extrato
  # (reuniões qualificadas do SDR, contratos limpos do Closer).
  def meta_mes(grupo)
    metas = grupo.filter_map { |pessoa| pessoa[:meta] }
    {
      mes: mes.strftime('%Y-%m'), meta: metas.presence&.sum, realizado: grupo.sum { |pessoa| pessoa[:contagem] },
      dias_uteis_restantes: dias_uteis_restantes
    }
  end

  def agora
    @agora ||= Time.current.in_time_zone(TIME_ZONE)
  end

  # Mês da meta: o passado em "mes_passado"; senão o corrente (hoje/semana também).
  def mes
    (periodo == 'mes_passado' ? agora.to_date.prev_month : agora.to_date).beginning_of_month
  end

  def intervalo_do_mes
    inicio = ActiveSupport::TimeZone[TIME_ZONE].local(mes.year, mes.month, 1)
    inicio...(inicio + 1.month)
  end

  def intervalo
    @intervalo ||= case periodo
                   when 'hoje' then agora.beginning_of_day...(agora.beginning_of_day + 1.day)
                   when 'semana' then agora.beginning_of_week...(agora.beginning_of_week + 1.week)
                   else intervalo_do_mes
                   end
  end

  # Dias úteis (seg–sex, sem feriados) de hoje ao fim do mês corrente; mês passado = 0.
  def dias_uteis_restantes
    return 0 if periodo == 'mes_passado'

    (agora.to_date..agora.to_date.end_of_month).count { |dia| !dia.saturday? && !dia.sunday? }
  end
end
