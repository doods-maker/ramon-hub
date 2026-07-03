class Api::V1::Accounts::RamonDashboardController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 10

  before_action :current_account
  before_action :check_authorization

  def show
    @today = today_section
    @funnel = funnel_section
    @week = week_section
  end

  private

  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  # ---- Hoje -------------------------------------------------------------

  def today_section
    {
      tasks_overdue: block(account_tasks.overdue.order(:due_at)),
      tasks_today: block(account_tasks.due_today.order(:due_at)),
      stalled: block(stalled_leads),
      no_next_action: block(no_next_action_leads),
      new_from_lp: block(new_from_lp_leads)
    }
  end

  # count sempre total da relação; items limitado a LIST_LIMIT.
  def block(relation)
    { count: relation.count, items: relation.limit(LIST_LIMIT) }
  end

  def account_tasks
    Current.account.lead_tasks.includes(:lead)
  end

  def active_leads
    Current.account.leads.joins(:lead_stage).where(lead_stages: { is_won: false, is_lost: false })
  end

  def stalled_leads
    active_leads.where.not(lead_stages: { stalled_after_days: nil })
                .where("leads.stage_entered_at < NOW() - (lead_stages.stalled_after_days || ' days')::interval")
  end

  def no_next_action_leads
    active_leads.where.not(id: Current.account.lead_tasks.open_tasks.select(:lead_id))
  end

  def new_from_lp_leads
    Current.account.leads
           .where.not(source: [nil, ''])
           .where(conversation_id: nil, created_at: 48.hours.ago..)
           .where.not(id: Current.account.lead_notes.select(:lead_id))
           .where.not(id: Current.account.lead_tasks.select(:lead_id))
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
      count: count, total_value: total,
      weighted_value: (total * stage.probability) / 100,
      is_won: stage.is_won, is_lost: stage.is_lost
    }
  end

  # ---- Semana -----------------------------------------------------------

  def week_section
    {
      created_by_source: created_by_source,
      won: Current.account.leads.where(won_at: 7.days.ago..).count,
      lost: Current.account.leads.where(lost_at: 7.days.ago..).count,
      created: Current.account.leads.where(created_at: 7.days.ago..).count,
      lost_reasons_30d: lost_reasons_30d
    }
  end

  def created_by_source
    Current.account.leads.where(created_at: 7.days.ago..)
           .reorder(nil).group(:source).count
           .sort_by { |_source, count| -count }
  end

  def lost_reasons_30d
    Current.account.leads.where(lost_at: 30.days.ago..)
           .reorder(nil).group(:lost_reason).count
           .sort_by { |_reason, count| -count }
  end
end
