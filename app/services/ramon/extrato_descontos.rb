# Desconto na apuração seguinte (regulamento §5.2 e §4-A). Contrato limpo que
# já entrou num extrato FECHADO e depois saiu de Fechado (leads.contrato_cancelado_em
# dentro do mês apurado) volta como linha negativa com o mesmo valor da unidade.
# Se a saída da contagem desfizer bônus/degrau pago naquele mês (Closer: a meta
# conta contratos limpos), a diferença do bônus vem numa segunda linha.
# Sem desconto em dobro: o lead só é descontado enquanto tem mais unidades pagas
# do que descontos nos extratos fechados da pessoa (as linhas de desconto ficam
# guardadas no payload do mês em que entraram).
class Ramon::ExtratoDescontos
  DESCONTO = 'desconto'.freeze
  DESCONTO_BONUS = 'desconto_bonus'.freeze
  CONTRATO = 'contrato_limpo'.freeze

  pattr_initialize [:account!, :user!, :papel!, :mes!, :periodo!]

  def linhas
    @gerados = Hash.new(0)
    cancelados.flat_map { |lead| linhas_do(lead) }
  end

  private

  def cancelados
    account.leads.reorder(nil).where(id: pagos_sem_desconto.keys, contrato_cancelado_em: periodo).order(:contrato_cancelado_em)
  end

  def fechados
    @fechados ||= ExtratoFechado.where(account: account, user: user, papel: papel)
                                .where(competencia: ...mes).order(:competencia).to_a
  end

  def linhas_fechadas
    @linhas_fechadas ||= fechados.flat_map { |registro| registro.payload['unidades'].map { |u| [registro, u] } }
  end

  # lead_id => extrato fechado mais recente em que a unidade foi paga (só os ainda não descontados).
  def pagos_sem_desconto
    @pagos_sem_desconto ||= linhas_fechadas.select { |_registro, u| u['evento'] == CONTRATO }
                                           .group_by { |_registro, u| u['lead_id'] }
                                           .filter_map { |id, pagas| [id, pagas.last] if pagas.size > descontados.fetch(id, 0) }.to_h
  end

  def descontados
    @descontados ||= linhas_fechadas.filter_map { |_registro, u| u['lead_id'] if u['evento'] == DESCONTO }.tally
  end

  def linhas_do(lead)
    origem, unidade = pagos_sem_desconto[lead.id]
    [linha(lead, origem, DESCONTO, -unidade['valor']), bonus_desfeito(lead, origem)].compact
  end

  # §4-A: o contrato descontado sai da contagem do mês de origem; se isso desfaz
  # o bônus ou um degrau já pago, compensa junto.
  def bonus_desfeito(lead, origem)
    return unless Ramon::ExtratoVariavel::EVENTO_DA_META[papel] == CONTRATO

    payload = origem.payload
    ja_descontados = descontos_da_origem(origem) + @gerados[origem.id]
    @gerados[origem.id] += 1
    antes = bonus(payload, payload['contagem'] - ja_descontados)
    depois = bonus(payload, payload['contagem'] - ja_descontados - 1)
    linha(lead, origem, DESCONTO_BONUS, depois - antes) if depois < antes
  end

  def descontos_da_origem(origem)
    linhas_fechadas.count { |_registro, u| u['evento'] == DESCONTO && u['competencia_origem'] == origem.competencia.iso8601 }
  end

  def bonus(payload, contagem)
    Ramon::ExtratoVariavel.bonus(Ramon::ExtratoVariavel::REGRAS.fetch(papel), contagem, payload['meta'].to_i).first
  end

  def linha(lead, origem, evento, valor)
    { data: lead.contrato_cancelado_em.iso8601, lead_id: lead.id, lead_nome: lead.name, evento: evento, valor: valor,
      competencia_origem: origem.competencia.iso8601 }
  end
end
