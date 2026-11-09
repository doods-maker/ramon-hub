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

  def ids_do_time
    MetaComercial::PAPEIS.flat_map { |papel| Ramon::Papeis.membro_ids(account, papel) }
  end

  def papel_de(user_id)
    metas[user_id]&.papel || ultima_meta(user_id)&.papel ||
      (Ramon::Papeis.membro_ids(account, Ramon::Papeis::SDR).include?(user_id) ? Ramon::Papeis::SDR : Ramon::Papeis::CLOSER)
  end

  def ultima_meta(user_id)
    MetaComercial.where(account: account, user_id: user_id).where(mes: ...mes).order(:mes).last
  end

  def linha(user, papel)
    meta = metas[user.id]
    base = papel == Ramon::Papeis::HIBRIDO ? hibrido(user) : modelo_a(user, papel, meta)
    variavel = base.delete(:soma).round(2)
    dsr = (variavel * razao_dsr).round(2)
    bonus = base.delete(:bonus) || []
    { user: { id: user.id, name: user.name }, papel: papel, variavel: variavel.to_f, dsr: dsr.to_f, bonus: bonus,
      total: (variavel + dsr + bonus.sum { |b| b[:valor] }).round(2).to_f }.merge(base)
  end

  def modelo_a(user, papel, meta)
    grade = GRADES.fetch(papel)
    alvo = meta&.meta.to_i.positive? ? meta.meta : grade[:meta]
    fator = (meta&.fator || 1).to_d
    unidades = unidades_a(user, papel).each_with_index.map do |(lead, data, evento), i|
      unidade(lead, data, evento, i < alvo ? grade[:ate_a_meta] : grade[:acima])
    end
    { meta: alvo, fator: fator.to_f, contagem: unidades.size, unidades: unidades, soma: soma(unidades) * fator }
  end

  def unidades_a(user, papel)
    return reunioes(user).map { |lead, data| [lead, data, REUNIAO] } if papel == Ramon::Papeis::SDR

    aptos(user).map { |lead, data| [lead, data, APTO] }
  end

  def hibrido(user)
    unidades = aptos(user).map { |lead, data| unidade(lead, data, APTO, comissao(lead)) }
    { meta: nil, fator: 1.0, contagem: unidades.size, unidades: unidades, soma: soma(unidades),
      sem_valor: aptos(user).count { |lead, _| comissao(lead).nil? }, bonus: bonus_do_programa(user, unidades.size) }
  end

  # nil = tese sem comissão no híbrido (não paga; o extrato conta quantos)
  def comissao(lead) = lead.thesis&.comissao_apto&.to_f

  def soma(unidades) = unidades.sum { |u| u[:valor].to_d }

  def bonus_do_programa(user, contagem)
    regras = ProgramaMetas.do_mes(account, mes)&.regras || {}
    [faixa(regras, contagem), gas(regras, contagem), constancia(user)].compact
  end

  # faixa mais alta atingida no mês (não somam)
  def faixa(regras, contagem)
    atingida = Array(regras['faixas']).select { |f| contagem >= f['min'].to_i }.max_by { |f| f['min'].to_i }
    atingida && { tipo: 'faixa', valor: atingida['valor'].to_f }
  end

  def gas(regras, contagem)
    acima = contagem - regras.dig('gas', 'acima_de').to_i
    return unless regras['gas'] && acima.positive?

    { tipo: 'gas', valor: (acima * regras['gas']['valor'].to_d).to_f }
  end

  # Constância do trimestre que terminou no mês anterior: mínimo de aptos em CADA mês e no máximo X% de problemas
  # (devolvidos pelo jurídico ou cancelados depois de aptos) sobre os enviados à validação (contrato limpo) no trimestre.
  def constancia(user)
    programa = ProgramaMetas.encerrado_antes_de(account, mes)
    regra = programa&.regras&.dig('constancia')
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
    devolvidos = LeadActivity.where(lead_id: dele.select(:id), kind: 'apto_devolvido', created_at: trimestre).distinct.pluck(:lead_id)
    cancelados = dele.where.not(apto_em: nil).where(contrato_cancelado_em: trimestre).pluck(:id)
    (devolvidos | cancelados).size
  end

  def reunioes(user)
    leads.where(sdr_id: user.id, reuniao_resultado: 'qualificada', reuniao_registrada_em: periodo)
         .order(:reuniao_registrada_em).map { |lead| [lead, lead.reuniao_registrada_em] }
  end

  def aptos(user, intervalo = periodo)
    @aptos ||= {}
    @aptos[[user.id, intervalo]] ||= leads.includes(:thesis).where(closer_id: user.id, apto_em: intervalo)
                                          .order(:apto_em).map { |lead| [lead, lead.apto_em] }
  end

  def unidade(lead, data, evento, valor)
    { data: data.iso8601, lead_id: lead.id, lead_nome: lead.name, tese: lead.thesis&.name, evento: evento, valor: valor }
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
    @metas ||= MetaComercial.where(account: account, mes: mes).index_by(&:user_id)
  end

  def periodo = periodo_de(mes)

  def periodo_de(data)
    inicio = ActiveSupport::TimeZone[TIME_ZONE].local(data.year, data.month, 1)
    inicio...(inicio + 1.month)
  end
end
