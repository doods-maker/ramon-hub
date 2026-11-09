# Fator de qualidade do trimestre (modelo A; `operacao-comercial\03-remuneracao.md` §3; decisões do Eduardo 09/11/2026).
# Trimestres fev–abr, mai–jul, ago–out, nov–jan. O fator vale no trimestre SEGUINTE ao medido:
#   SDR:    comparecimento = realizadas ÷ (realizadas + faltas)     < 65% → 0,8 · 65–80% → 1,0 · > 80% → 1,1
#   Closer: devolvidos pelo jurídico ou cancelados até 90 dias depois de aptos ÷ enviados à validação
#                                                                     > 15% → 0,8 · 5–15% → 1,0 · ≤ 5% → 1,1
# O 1º trimestre da pessoa (entrou no time ou teve a 1ª meta dentro dele) é 1,0. Calculado na 1ª leitura com o trimestre
# já começado e guardado (FatorQualidade): o extrato não muda depois. O gestor corrige digitando o fator na meta de um
# mês do trimestre (vale o mais recente do trimestre).
module Ramon::FatorTrimestre
  INICIOS = [2, 5, 8, 11].freeze
  ZONA = 'America/Sao_Paulo'.freeze

  module_function

  # @return [Hash] { fator: Float, base: Hash } — base: tipo, numerador, denominador, taxa, trimestre_base, manual, primeiro
  def de(account, user, papel, mes, metas: nil)
    inicio = inicio_do_trimestre(mes)
    manual = Array(metas).reverse.find { |m| m.mes >= inicio && m.fator }
    return { fator: manual.fator.to_f, base: { manual: true } } if manual
    return { fator: 1.0, base: { manual: false, futuro: true } } if hoje < inicio

    guardado = FatorQualidade.find_or_create_by!(account: account, user: user, papel: papel, inicio: inicio) do |r|
      r.fator, r.base = calcular(account, user, papel, inicio)
    end
    { fator: guardado.fator.to_f, base: guardado.base.symbolize_keys.merge(manual: false) }
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def inicio_do_trimestre(mes)
    inicio = INICIOS.select { |m| m <= mes.month }.max
    inicio ? Date.new(mes.year, inicio, 1) : Date.new(mes.year - 1, 11, 1)
  end

  def calcular(account, user, papel, inicio)
    anterior = periodo(inicio << 3, inicio)
    return [1.0, { primeiro: true }] if primeiro_trimestre?(account, user, inicio)

    num, den, tipo = papel == Ramon::Papeis::SDR ? comparecimento(account, user, anterior) : problemas(account, user, anterior)
    taxa = den.zero? ? nil : num.fdiv(den).round(4)
    [faixa(tipo, taxa), { tipo: tipo, numerador: num, denominador: den, taxa: taxa, trimestre_base: (inicio << 3).iso8601 }]
  end

  def faixa(tipo, taxa)
    return 1.0 if taxa.nil?
    return (taxa < 0.65 ? 0.8 : (taxa > 0.80 ? 1.1 : 1.0)) if tipo == 'comparecimento' # rubocop:disable Style/NestedTernaryOperator

    taxa > 0.15 ? 0.8 : (taxa > 0.05 ? 1.0 : 1.1) # rubocop:disable Style/NestedTernaryOperator
  end

  # [realizadas, realizadas + faltas]
  def comparecimento(account, user, periodo)
    dele = account.leads.where(sdr_id: user.id)
    realizadas = dele.where(reuniao_registrada_em: periodo).count
    faltas = LeadActivity.where(lead_id: dele.select(:id), kind: 'meeting_no_show', created_at: periodo).count
    [realizadas, realizadas + faltas, 'comparecimento']
  end

  # [problemas, enviados]: devolvidos no período ∪ aptos do período cancelados até 90 dias depois
  def problemas(account, user, periodo)
    dele = account.leads.where(closer_id: user.id)
    enviados = dele.where(contrato_limpo_em: periodo).count
    devolvidos = LeadActivity.where(lead_id: dele.select(:id), kind: 'apto_devolvido', created_at: periodo).pluck(:lead_id)
    cancelados = dele.where(apto_em: periodo).where.not(contrato_cancelado_em: nil)
                     .where("contrato_cancelado_em <= apto_em + INTERVAL '90 days'").pluck(:id)
    [(devolvidos | cancelados).size, enviados, 'problemas']
  end

  # entrou no time (sdr/closer) ou teve a 1ª meta dentro deste trimestre
  def primeiro_trimestre?(account, user, inicio)
    entrada = [MetaComercial.where(account: account, user: user).minimum(:mes),
               TeamMember.joins(:team).where(user: user, teams: { account_id: account.id, name: Ramon::Papeis::COLUNA.keys })
                         .minimum(:created_at)&.in_time_zone(ZONA)&.to_date].compact.min
    entrada.nil? || entrada >= inicio
  end

  def periodo(desde, ate)
    zona = ActiveSupport::TimeZone[ZONA]
    zona.local(desde.year, desde.month, 1)...zona.local(ate.year, ate.month, 1)
  end

  def hoje = Time.current.in_time_zone(ZONA).to_date
end
