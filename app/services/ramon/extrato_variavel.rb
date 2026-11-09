# Extrato mensal da variável por pessoa, nas duas grades decididas pelo Eduardo em 09/11/2026
# (comercial\docs\2026-11-09-briefing-hub-extrato-duas-grades.md; plano 2026-11-09-extrato-duas-grades):
# - modelo A, SDR e Closer separados (`operacao-comercial\03-remuneracao.md`): valor por unidade até a meta do mês e
#   outro acima dela, na ordem em que as unidades aconteceram, × fator de qualidade do trimestre (MetaComercial#fator);
# - modelo B, híbrido (kit `contratacao\02` e `09`): comissão da tese por contrato apto (Thesis#comissao_apto) + Programa
#   de Metas do trimestre (ProgramaMetas: faixa do mês, gás acima de N e constância no mês seguinte ao trimestre).
# DSR sobre a variável (Súmula 27/TST): × (domingos e feriados ÷ dias de seg a sáb). Bônus do Programa sem DSR por cima.
# Contrato apto = Ramon::ContratoApto; depois de apto a comissão é devida, então não há desconto em mês seguinte.
# Pessoas = times `sdr`/`closer` + quem tem meta lançada no mês. Papel = meta do mês → última meta lançada → time.
# Quem recebe é o SDR/Closer que ESTÁ no lead na hora da apuração.
class Ramon::ExtratoVariavel
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  # Modelo A. Mudou a grade, muda aqui (e no 03-remuneracao).
  GRADES = {
    Ramon::Papeis::SDR => { meta: 50, ate_a_meta: 8, acima: 12 },
    Ramon::Papeis::CLOSER => { meta: 20, ate_a_meta: 30, acima: 45 }
  }.freeze
  REUNIAO = 'reuniao_qualificada'.freeze
  APTO = 'contrato_apto'.freeze

  APTO_POR_PRAZO = 'contrato_apto_prazo'.freeze

  pattr_initialize [:account!, :mes!]

  def pessoas
    pares.map { |user, papel| linha(user, papel) }
  end

  private

  def pares
    users = User.where(id: ids_do_time | metas.keys).index_by(&:id)
    users.values.map { |user| [user, papel_de(user.id)] }
         .sort_by { |user, papel| [MetaComercial::PAPEIS.index(papel), user.name.to_s] }
  end

  # o híbrido fica no time `closer` (não há time `hibrido`)
  def ids_do_time = sdr_ids | Ramon::Papeis.membro_ids(account, Ramon::Papeis::CLOSER)

  def sdr_ids = @sdr_ids ||= Ramon::Papeis.membro_ids(account, Ramon::Papeis::SDR)

  # Papel e fator vigentes = a última meta lançada até este mês; sem nenhuma, o time.
  def vigente(user_id) = historico[user_id]&.last

  def papel_de(user_id)
    vigente(user_id)&.papel || (sdr_ids.include?(user_id) ? Ramon::Papeis::SDR : Ramon::Papeis::CLOSER)
  end

  # 1º mês da pessoa = o mês da 1ª meta lançada para ela (o gestor lança na admissão)
  def primeiro_mes?(user_id) = historico[user_id]&.first&.mes == mes

  def linha(user, papel)
    base = papel == Ramon::Papeis::HIBRIDO ? hibrido(user) : modelo_a(user, papel)
    variavel = base[:soma].round(2)
    dsr = (variavel * razao_dsr).round(2)
    bonus = base[:bonus] || []
    { user: { id: user.id, name: user.name }, papel: papel, variavel: variavel.to_f, dsr: dsr.to_f, bonus: bonus,
      total: (variavel + dsr + bonus.sum { |b| b[:valor].to_d }).round(2).to_f }.merge(base.except(:soma, :bonus))
  end

  def modelo_a(user, papel)
    grade = GRADES.fetch(papel)
    alvo = alvo_do_mes(user.id, grade)
    fator = (vigente(user.id)&.fator || 1).to_d
    unidades = eventos_a(user, papel).each_with_index.map do |(lead, data, evento), i|
      unidade(lead, data, evento, i < alvo ? grade[:ate_a_meta] : grade[:acima])
    end
    { meta: alvo, fator: fator.to_f, contagem: unidades.size, unidades: unidades, soma: soma(unidades) * fator }
  end

  # meta lançada NESTE mês; sem ela, a padrão da grade
  def alvo_do_mes(user_id, grade)
    lancada = metas[user_id]&.meta.to_i
    lancada.positive? ? lancada : grade[:meta]
  end

  def eventos_a(user, papel)
    papel == Ramon::Papeis::SDR ? reunioes(user).map { |lead, data| [lead, data, REUNIAO] } : aptos_com_evento(user)
  end

  # Modelo B. Mês de admissão: só comissão (o Programa começa no 1º mês cheio).
  def hibrido(user)
    unidades = aptos_com_evento(user).map { |lead, data, evento| unidade(lead, data, evento, lead.thesis&.comissao_apto || 0) }
    bonus = primeiro_mes?(user.id) ? [] : bonus_do_programa(user, unidades.size)
    { meta: nil, fator: 1.0, contagem: unidades.size, unidades: unidades, soma: soma(unidades), bonus: bonus,
      sem_valor: aptos(user).count { |lead, _| lead.thesis&.comissao_apto.nil? } }
  end

  def aptos_com_evento(user)
    aptos(user).map { |lead, data| [lead, data, lead.apto_por_id ? APTO : APTO_POR_PRAZO] }
  end

  def soma(unidades) = unidades.sum { |u| u[:valor].to_d }

  def bonus_do_programa(user, contagem)
    Array(ProgramaMetas.do_mes(account, mes)&.bonus_do_mes(contagem)) + [constancia(user)].compact
  end

  # Constância do trimestre que terminou no mês anterior: mínimo de aptos em CADA mês e no máximo X% de problemas
  # (devolvidos pelo jurídico ou cancelados depois de aptos) sobre os enviados à validação (contrato limpo) no trimestre.
  def constancia(user)
    programa = ProgramaMetas.encerrado_antes_de(account, mes)
    regra = programa&.regras&.dig('constancia')
    return if primeiro_mes?(user.id)
    return unless regra && minimo_todo_mes?(user, programa, regra['min_mes'].to_i)

    return if taxa_de_problemas(user, periodo_de(programa.inicio).first...periodo_de(programa.fim).last) > regra['max_problemas'].to_f

    { tipo: 'constancia', valor: regra['valor'].to_f }
  end

  # sem nenhum enviado no trimestre = 100% (não paga)
  def taxa_de_problemas(user, trimestre)
    enviados = leads.where(closer_id: user.id, contrato_limpo_em: trimestre).count
    enviados.zero? ? 1.0 : problemas(user, trimestre).fdiv(enviados)
  end

  def minimo_todo_mes?(user, programa, minimo)
    (programa.inicio..programa.fim).map(&:beginning_of_month).uniq.all? { |m| aptos(user, periodo_de(m)).size >= minimo }
  end

  def problemas(user, trimestre)
    dele = leads.where(closer_id: user.id)
    devolvidos = LeadActivity.where(lead_id: dele.select(:id), kind: 'apto_devolvido', created_at: trimestre).pluck(:lead_id)
    cancelados = dele.where.not(apto_em: nil).where(contrato_cancelado_em: trimestre).pluck(:id)
    (devolvidos | cancelados).size
  end

  def reunioes(user)
    leads.includes(:thesis).where(sdr_id: user.id, reuniao_resultado: 'qualificada', reuniao_registrada_em: periodo)
         .order(:reuniao_registrada_em).map { |lead| [lead, lead.reuniao_registrada_em] }
  end

  def aptos(user, intervalo = periodo)
    @aptos ||= {}
    @aptos[[user.id, intervalo]] ||= leads.includes(:thesis).where(closer_id: user.id, apto_em: intervalo)
                                          .order(:apto_em).map { |lead| [lead, lead.apto_em] }
  end

  def unidade(lead, data, evento, valor)
    { data: data.iso8601, lead_id: lead.id, lead_nome: lead.name, tese: lead.thesis&.name, evento: evento, valor: valor.to_f }
  end

  # domingos e feriados ÷ dias de seg a sáb (feriados de Ramon::Agenda::Feriados)
  def razao_dsr
    @razao_dsr ||= begin
      dias = mes.all_month.to_a
      descanso = dias.count { |dia| dia.sunday? || Ramon::Agenda::Feriados.feriado?(dia) }
      descanso.to_d / (dias.size - descanso)
    end
  end

  def leads
    account.leads.funil.reorder(nil)
  end

  def metas
    @metas ||= historico.transform_values(&:last).select { |_, meta| meta.mes == mes }
  end

  # metas lançadas até este mês, por pessoa, em ordem
  def historico
    @historico ||= MetaComercial.where(account: account, mes: ..mes).order(:mes).group_by(&:user_id)
  end

  def periodo = periodo_de(mes)

  def periodo_de(data)
    inicio = ActiveSupport::TimeZone[TIME_ZONE].local(data.year, data.month, 1)
    inicio...(inicio + 1.month)
  end
end
