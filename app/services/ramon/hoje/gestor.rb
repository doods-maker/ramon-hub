# Tela Hoje do gestor: o que precisa dele, o time no dia, o mês e o funil agora.
class Ramon::Hoje::Gestor
  pattr_initialize [:account!]

  def perform
    { precisa: precisa, time: time_hoje, mes: mes, funil: funil }
  end

  private

  def zona = Time.find_zone!(Chegada::ZONA)
  def hoje = zona.now.all_day
  def mes_atual = zona.now.all_month
  def leads = account.leads.funil.reorder(nil)

  def precisa
    [sla, parado, docs, conteudo].compact
  end

  def sla
    atrasados = Ramon::Hoje::Prazo.estourados(account.leads).to_a
    { tipo: 'sla', nivel: 'bad', count: atrasados.size, nomes: atrasados.first(3).map(&:name) } if atrasados.any?
  end

  # A etapa com mais leads parados (threshold da própria etapa).
  def parado
    grupos = Ramon::Cadencia.parados(account.leads.open.reorder(nil)).group('lead_stages.name', 'lead_stages.stalled_after_days').count
    return if grupos.empty?

    (etapa, dias), count = grupos.max_by { |_chave, total| total }
    { tipo: 'parado', nivel: 'warn', count: count, etapa: etapa, dias: dias }
  end

  def docs
    count = Ramon::LeadRadar.pos_venda(account)[:pendentes].count { |lead| lead.won_at < 7.days.ago }
    { tipo: 'docs', nivel: 'warn', count: count } if count.positive?
  end

  def conteudo
    pecas = Peca.where(account: account, status: 'rascunho').order(:created_at)
    { tipo: 'conteudo', nivel: 'act', count: pecas.count, nomes: pecas.limit(2).pluck(:gancho) } if pecas.exists?
  end

  def time_hoje
    { sdr: sdr_hoje, closer: closer_hoje, recepcao: { chegadas: Chegada.where(account: account).de_hoje.count } }
  end

  def sdr_hoje
    respondidas = Ramon::Cadencia.sla_conversations(account, hoje).where.not(first_reply_created_at: nil)
    { respondidos: respondidas.count, media_minutos: Ramon::CockpitMetrics.new(account).sla_today[:avg_first_response_minutes] }
  end

  def closer_hoje
    { reunioes: account.lead_tasks.where(kind: 'meeting', due_at: hoje).count, contratos: leads.where(won_at: hoje).count }
  end

  def mes
    ganhos = leads.where(won_at: mes_atual)
    total = ganhos.count
    {
      contratos: total, ganhos_mes: total, docs_completos: ganhos.where.not(docs_completos_em: nil).count,
      reunioes_qualificadas: leads.where(reuniao_resultado: 'qualificada', reuniao_registrada_em: mes_atual).count,
      meta_contratos: meta_contratos
    }
  end

  # Soma das metas dos closers no mês; 0 = sem meta (nil → o front mostra só o número).
  def meta_contratos
    MetaComercial.where(account: account, papel: Ramon::Papeis::CLOSER, mes: zona.today.beginning_of_month).sum(:meta).nonzero?
  end

  def funil
    contagem = leads.group(:lead_stage_id).count
    account.lead_stages.where(is_won: false, is_lost: false).reorder(:position)
           .map { |etapa| { etapa: etapa.name, cor: etapa.color, count: contagem[etapa.id].to_i } }
  end
end
