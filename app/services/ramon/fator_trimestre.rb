# Fator de qualidade do trimestre (modelo A; `operacao-comercial\03-remuneracao.md` §3; decisões do Eduardo 09/11/2026).
# Trimestres fev–abr, mai–jul, ago–out, nov–jan. O fator vale no trimestre SEGUINTE ao medido:
#   SDR:    comparecimento = realizadas ÷ (realizadas + faltas)     < 65% → 0,8 · 65–80% → 1,0 · > 80% → 1,1
#   Closer: devolvidos pelo jurídico ou cancelados até 90 dias depois de aptos ÷ enviados à validação
#                                                                     > 15% → 0,8 · 5–15% → 1,0 · ≤ 5% → 1,1
# O 1º trimestre da pessoa (entrou no time ou teve a 1ª meta dentro dele) é 1,0. Conta só o que aconteceu até o 1º dia do
# trimestre novo (cancelamento depois disso não entra), então o número é o mesmo seja qual for o dia em que é lido; é
# guardado na 1ª leitura (FatorQualidade). O gestor corrige digitando o fator na meta de um mês do trimestre: vale daquele
# mês em diante (o mais recente até o mês) e o cartão continua mostrando o calculado.
module Ramon::FatorTrimestre
  INICIOS = [2, 5, 8, 11].freeze
  ZONA = 'America/Sao_Paulo'.freeze

  module_function

  # @return [Hash] { fator: Float, base: Hash } — base: tipo, numerador, denominador, taxa, trimestre_base, manual, primeiro
  def de(account, user, papel, mes, metas: nil)
    inicio = inicio_do_trimestre(mes)
    calculado = hoje < inicio ? { fator: 1.0, base: {} } : guardado(account, user, papel, inicio)
    manual = Array(metas).reverse.find { |m| m.mes >= inicio && m.fator }
    return { fator: calculado[:fator], base: calculado[:base].merge(manual: false) } unless manual

    { fator: manual.fator.to_f, base: calculado[:base].merge(manual: true, calculado: calculado[:fator]) }
  end

  def guardado(account, user, papel, inicio)
    chave = { account: account, user: user, papel: papel, inicio: inicio }
    registro = FatorQualidade.find_by(chave) || criar(chave, calcular(account, user, papel, inicio))
    { fator: registro.fator.to_f, base: registro.base.symbolize_keys }
  end

  # outra leitura criou ao mesmo tempo: vale a dela
  def criar(chave, (fator, base))
    FatorQualidade.create!(chave.merge(fator: fator, base: base))
  rescue ActiveRecord::RecordNotUnique
    FatorQualidade.find_by!(chave)
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

    if tipo == 'comparecimento'
      return 0.8 if taxa < 0.65

      taxa > 0.80 ? 1.1 : 1.0
    else
      return 0.8 if taxa > 0.15

      taxa > 0.05 ? 1.0 : 1.1
    end
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
    cancelados = dele.where(apto_em: periodo, contrato_cancelado_em: ...periodo.last) # só o que se sabia no 1º dia
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
