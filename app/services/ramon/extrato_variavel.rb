# Extrato mensal da variável por pessoa (regulamento de remuneração v2,
# `comercial\contratacao\02-regulamento-remuneracao-variavel.md` §§3–7).
# Pessoas = times `sdr`/`closer` + quem tem meta lançada no mês (saiu do time
# no meio do mês e ainda precisa ser apurado).
# Quem recebe é o SDR/Closer que ESTÁ no lead na hora da apuração.
class Ramon::ExtratoVariavel
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  # Valores do regulamento v2 (vigência 03/11/2026). Mudou o regulamento, muda aqui.
  REGRAS = {
    Ramon::Papeis::SDR => { reuniao: 6, contrato: 10, bonus: 150, degrau: 150, teto: 1600, garantia: 300 },
    Ramon::Papeis::CLOSER => { contrato: 22, bonus: 150, degrau: 150, teto: 1800, garantia: 400 }
  }.freeze

  # Evento que conta pra meta: reuniões qualificadas (SDR), contratos limpos (Closer).
  EVENTO_DA_META = { Ramon::Papeis::SDR => 'reuniao_qualificada', Ramon::Papeis::CLOSER => 'contrato_limpo' }.freeze

  pattr_initialize [:account!, :mes!]

  def pessoas
    pares.map { |user, papel| linha(user, papel) }
  end

  private

  def pares
    lista = MetaComercial::PAPEIS.flat_map { |papel| Ramon::Papeis.membro_ids(account, papel).map { |id| [id, papel] } }
    lista |= metas.values.map { |meta| [meta.user_id, meta.papel] }
    users = User.where(id: lista.map(&:first)).index_by(&:id)
    lista.filter_map { |id, papel| [users[id], papel] if users[id] }
         .sort_by { |user, papel| [MetaComercial::PAPEIS.index(papel), user.name.to_s] }
  end

  def linha(user, papel)
    regras = REGRAS.fetch(papel)
    unidades = papel == Ramon::Papeis::SDR ? unidades_sdr(user, regras) : unidades_closer(user, regras)
    meta = metas[user.id]
    contagem = unidades.count { |u| u[:evento] == EVENTO_DA_META[papel] }
    {
      user: { id: user.id, name: user.name }, papel: papel,
      meta: meta&.meta, rampa: meta&.rampa || false, contagem: contagem, unidades: unidades
    }.merge(calculo(regras, unidades.sum { |u| u[:valor] }, contagem, meta))
  end

  # §4-A: bateu a meta = +bônus; cada degrau de 20% da meta (arredondado pra
  # cima) acima dela = +degrau. §7: rampa garante o mínimo sobre as unidades,
  # bônus por cima. O teto vale pra unidades + bônus.
  def calculo(regras, subtotal, contagem, meta)
    alvo = meta&.meta.to_i
    bateu = alvo.positive? && contagem >= alvo
    degraus = bateu ? (contagem - alvo) / ((alvo + 4) / 5) : 0
    bonus = bateu ? regras[:bonus] + (degraus * regras[:degrau]) : 0
    base = meta&.rampa ? [subtotal, regras[:garantia]].max : subtotal
    { subtotal: subtotal, degraus: degraus, bonus: bonus, garantia_aplicada: base > subtotal, total: [base + bonus, regras[:teto]].min }
  end

  # SDR: reunião qualificada + contrato limpo que ele originou (lead com SDR e
  # reunião registrada — regulamento §2 "originado pelo SDR").
  def unidades_sdr(user, regras)
    reunioes = leads.where(sdr_id: user.id, reuniao_resultado: 'qualificada', reuniao_registrada_em: periodo)
                    .map { |lead| unidade(lead, lead.reuniao_registrada_em, 'reuniao_qualificada', regras[:reuniao]) }
    contratos = leads.where(sdr_id: user.id, contrato_limpo_em: periodo).where.not(reuniao_resultado: nil)
                     .map { |lead| unidade(lead, lead.contrato_limpo_em, 'contrato_limpo', regras[:contrato]) }
    (reunioes + contratos).sort_by { |u| u[:data] }
  end

  def unidades_closer(user, regras)
    leads.where(closer_id: user.id, contrato_limpo_em: periodo)
         .map { |lead| unidade(lead, lead.contrato_limpo_em, 'contrato_limpo', regras[:contrato]) }
         .sort_by { |u| u[:data] }
  end

  def unidade(lead, data, evento, valor)
    { data: data.iso8601, lead_id: lead.id, lead_nome: lead.name, evento: evento, valor: valor }
  end

  def leads
    account.leads.funil.reorder(nil)
  end

  def metas
    @metas ||= MetaComercial.where(account: account, mes: mes).index_by(&:user_id)
  end

  def periodo
    inicio = ActiveSupport::TimeZone[TIME_ZONE].local(mes.year, mes.month, 1)
    inicio...(inicio + 1.month)
  end
end
