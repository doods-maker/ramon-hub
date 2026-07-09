class Api::V1::Accounts::RamonDashboardController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 10

  before_action :current_account
  before_action :check_authorization

  def show
    @today = today_section
    @funnel = funnel_section
    @week = week_section
    @history = history_section
  end

  private

  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  # ---- Hoje -------------------------------------------------------------

  def today_section
    {
      tasks_overdue: limited_block(account_tasks.overdue.order(:due_at)),
      tasks_today: limited_block(account_tasks.due_today.order(:due_at)),
      stalled: limited_block(stalled_leads),
      no_next_action: limited_block(no_next_action_leads),
      new_from_lp: limited_block(new_from_lp_leads)
    }
  end

  # count sempre total da relação; items limitado a LIST_LIMIT.
  def limited_block(relation)
    { count: relation.count, items: relation.limit(LIST_LIMIT) }
  end

  def account_tasks
    Current.account.lead_tasks.includes(:lead)
  end

  # Consultas compartilhadas com a Esteira vivem em Ramon::LeadRadar.
  def active_leads
    Ramon::LeadRadar.active_leads(Current.account)
  end

  def stalled_leads
    Ramon::LeadRadar.stalled_leads(Current.account)
  end

  def no_next_action_leads
    active_leads.where.not(id: Current.account.lead_tasks.open_tasks.select(:lead_id))
  end

  def new_from_lp_leads
    Ramon::LeadRadar.new_from_lp_leads(Current.account)
  end

  # ---- Funil ------------------------------------------------------------

  # 2 queries agregadas + stages em memória (sem N+1). reorder(nil) anula o
  # default_scope de ordenação do Lead, que quebra o GROUP BY no Postgres.
  def funnel_section
    counts = Current.account.leads.reorder(nil).group(:lead_stage_id).count
    values = Current.account.leads.reorder(nil).group(:lead_stage_id).sum(:value)
    Current.account.lead_stages.map do |stage|
      funnel_row(stage, counts[stage.id].to_i, values[stage.id] || 0)
    end
  end

  def funnel_row(stage, count, total)
    {
      stage_id: stage.id, name: stage.name, color: stage.color,
      count: count, total_value: total.to_f,
      weighted_value: (total.to_f * stage.probability) / 100,
      is_won: stage.is_won, is_lost: stage.is_lost
    }
  end

  # ---- Semana -----------------------------------------------------------

  def week_section
    {
      created_by_channel: created_by_channel,
      won: Current.account.leads.where(won_at: 7.days.ago..).count,
      lost: Current.account.leads.where(lost_at: 7.days.ago..).count,
      created: Current.account.leads.where(created_at: 7.days.ago..).count,
      lost_reasons_30d: lost_reasons_30d
    }
  end

  def created_by_channel
    counts = Current.account.leads.where(created_at: 7.days.ago..).reorder(nil).group(:channel).count
    Ramon::SourceCatalog::CHANNELS.map do |c|
      { key: c[:key], label: c[:label], count: counts[c[:key]].to_i }
    end
  end

  def lost_reasons_30d
    Current.account.leads.where(lost_at: 30.days.ago..)
           .reorder(nil).group(:lost_reason).count
           .sort_by { |_reason, count| -count }
  end

  # ---- Histórico (snapshots diários) ------------------------------------

  # 2 sums agregadas por dia sobre etapas abertas (estoque de pipeline vivo).
  def history_section
    scope = FunnelSnapshot.where(account_id: Current.account.id, is_won: false, is_lost: false)
                          .where(snapshot_date: 29.days.ago.to_date..)
    counts = scope.group(:snapshot_date).sum(:leads_count)
    values = scope.group(:snapshot_date).sum(:value_sum)
    counts.keys.sort.map do |date|
      { date: date, leads_count: counts[date].to_i, value_sum: values[date].to_f }
    end
  end
end
