# Números do resumo diário das 8h (mock 3f): push ntfy pro SDR + e-mail de
# gestão. Queries próprias e enxutas (escopo Lead.funil) — mesmo critério do
# Cockpit, mas sem depender do Ramon::CockpitMetrics (outro dono, outra
# cadência de mudança).
class Ramon::DailyDigestService
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  WDAYS = %w[domingo segunda terça quarta quinta sexta sábado].freeze
  MONTHS = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze

  def initialize(account:)
    @account = account
  end

  # Corpo do push em 1 linha; partes zeradas caem fora; tudo zerado → nil
  # (o job não manda nada).
  def push_body
    [overdue_part, sla_part, meeting_part, at_stake_part].compact.join(' · ').presence
  end

  # Stats de ontem pro e-mail de gestão, já formatados pro template.
  def yesterday_stats
    {
      date_label: date_label,
      new_leads: leads_funil.where(created_at: yesterday_range).reorder(nil).count,
      won: won_stats,
      lost: lost_stats,
      first_response_label: first_response_label
    }
  end

  private

  # ---- Partes do push -----------------------------------------------------

  def overdue_part
    count = overdue_funil_tasks.count
    return if count.zero?

    count == 1 ? '1 tarefa vencida' : "#{count} tarefas vencidas"
  end

  def sla_part
    count = sla_breached_count
    "#{count} fora do SLA" unless count.zero?
  end

  def meeting_part
    task = next_meeting
    return if task.nil?

    label = hour_label(task.due_at.in_time_zone(TIME_ZONE))
    name = task.lead&.name
    name.present? ? "reunião #{label} (#{name})" : "reunião #{label}"
  end

  def at_stake_part
    value = value_at_stake
    "#{money_label(value)} em jogo" if value.positive?
  end

  # ---- Consultas ----------------------------------------------------------

  def leads_funil
    @account.leads.funil
  end

  def overdue_funil_tasks
    @account.lead_tasks.overdue.joins(:lead).merge(Lead.funil).reorder(nil)
  end

  # Mesmo critério do Cockpit: conversa nascida hoje em inbox de lead
  # (auto_create_lead) sem 1ª resposta além do SLA, ou respondida além dele.
  # N por conversa: SLA da própria inbox, com fallback no env (COALESCE por linha).
  def sla_breached_count
    threshold = sla_threshold_sql
    scope = sla_conversations(today_range)
    # Epoch em vez de aritmética de interval: o bind de Time entrava como
    # literal de tipo desconhecido e o PG tentava resolvê-lo como interval.
    waiting = scope.where(first_reply_created_at: nil)
                   .where("EXTRACT(EPOCH FROM (? - conversations.created_at)) / 60.0 > (#{threshold})", Time.current).count
    over = scope.where("EXTRACT(EPOCH FROM (first_reply_created_at - conversations.created_at)) / 60.0 > (#{threshold})").count
    waiting + over
  end

  # Interpolação segura: só o inteiro do env entra na string.
  def sla_threshold_sql
    "COALESCE(inboxes.first_response_sla_minutes, #{ENV.fetch('RAMON_SLA_FIRST_RESPONSE_MINUTES', '15').to_i})"
  end

  def sla_conversations(range)
    @account.conversations.joins(:inbox)
            .where(inboxes: { auto_create_lead: true })
            .where(conversations: { created_at: range })
  end

  # Próxima reunião ainda por vir hoje (aberta ou não — a agenda mostra o dia).
  def next_meeting
    @account.lead_tasks.where(kind: 'meeting')
            .where(due_at: Time.current..today_range.end)
            .order(:due_at).includes(:lead).first
  end

  # ponytail: "em jogo" = Σ benefit_monthly_value dos leads da fila de risco
  # (task vencida OU parado na etapa) — aproximação da fila de follow-up do
  # Cockpit, não do Kanban inteiro; refinar se o número enganar na prática.
  def value_at_stake
    ids = overdue_funil_tasks.distinct.pluck(:lead_id) | Ramon::LeadRadar.stalled_leads(@account).ids
    return 0.0 if ids.empty?

    leads_funil.where(id: ids).reorder(nil).sum(:benefit_monthly_value).to_f
  end

  # ---- Stats de ontem (e-mail) --------------------------------------------

  def won_stats
    values = leads_funil.where(won_at: yesterday_range).reorder(nil).pluck(:value)
    total = values.sum(&:to_f)
    { count: values.size, value_label: total.positive? ? money_label(total) : nil }
  end

  def lost_stats
    reasons = leads_funil.where(lost_at: yesterday_range).reorder(nil).group(:lost_reason).count
    top = reasons.max_by { |reason, count| [count, reason.to_s] }
    { count: reasons.values.sum, reason: top&.first.presence }
  end

  def first_response_label
    replied = sla_conversations(yesterday_range).where.not(first_reply_created_at: nil)
    avg = replied.average(Arel.sql('EXTRACT(EPOCH FROM (first_reply_created_at - conversations.created_at)) / 60.0'))
    "#{avg.to_f.round}min" if avg.present?
  end

  # ---- Formatação (fuso do escritório) ------------------------------------

  def now_brt
    @now_brt ||= Time.current.in_time_zone(TIME_ZONE)
  end

  def today_range
    now_brt.all_day
  end

  def yesterday_range
    (now_brt - 1.day).all_day
  end

  def date_label
    date = yesterday_range.begin.to_date
    "#{WDAYS[date.wday]}, #{date.day} de #{MONTHS[date.month - 1]}"
  end

  def hour_label(time)
    time.min.zero? ? "#{time.hour}h" : "#{time.hour}h#{format('%02d', time.min)}"
  end

  # ponytail: teto em "mil" (R$ 1500 mil se algum dia passar de milhão) —
  # trocar por "mi" só se o funil chegar lá.
  def money_label(value)
    return "R$ #{(value / 1000.0).round} mil" if value >= 1000

    "R$ #{value.round}"
  end
end
