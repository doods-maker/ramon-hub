# Reunião marcada — mesmo efeito venha do Cal.com (webhook) ou do painel do
# lead ("+ Tarefa" → Reunião): tarefa kind meeting, lead anda pra "Reunião
# agendada" (só pra frente), Closer automático, rascunho de confirmação nas
# notas (NUNCA enviado — quem envia é a pessoa), lembretes internos (sino +
# ntfy), atividade e aviso no sino.
class Ramon::ReuniaoAgendamento
  # ponytail: fork single-tenant do escritório (Tubarão/SC) — fuso fixo para o
  # texto humano; parametrizar se um dia houver mais contas.
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  DIAS_SEMANA = %w[domingo segunda terça quarta quinta sexta sábado].freeze
  STAGE_LABEL = 'fase-reuniao-agendada'.freeze

  # title = nome da reunião (atividade, sino); task_title = título da tarefa
  # (o Cal.com prefixa "Reunião Cal.com:" — o cancel/reschedule acham por ele).
  def self.call(lead:, starts_at:, title:, task_title: title, user: nil)
    new(lead, starts_at, title, user).call(task_title)
  end

  # "quinta, 20/08 às 14:00" — texto único pra sino e rascunho.
  def self.quando(starts_at)
    local = starts_at.in_time_zone(TIME_ZONE)
    "#{DIAS_SEMANA[local.wday]}, #{local.strftime('%d/%m')} às #{local.strftime('%H:%M')}"
  end

  # Sino do hub pra todo mundo da conta + push no celular na hora (o job é
  # no-op sem NTFY_TOPIC); os lembretes têm o seu no MeetingReminderJob.
  def self.notify(lead, type, starts_at, title)
    quando = starts_at ? quando(starts_at) : ''
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: type, meta: { 'quando' => quando }).perform
    verbo = type == 'ramon_meeting_cancelled' ? 'cancelada' : 'marcada'
    Ramon::NtfyPushJob.perform_later(lead.id, title: "Reuniao #{verbo}: #{lead.name}", body: "#{quando} — #{title}")
  end

  # "Primeiro Atendimento em 20/08/2026 14:00" — to_value da atividade.
  def self.resumo(title, starts_at)
    when_text = starts_at ? starts_at.in_time_zone(TIME_ZONE).strftime('%d/%m/%Y %H:%M') : ''
    "#{title} em #{when_text}".strip.truncate(255)
  end

  def initialize(lead, starts_at, title, user)
    @lead = lead
    @starts_at = starts_at
    @title = title
    @user = user
  end

  def call(task_title)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_scheduled',
                                  to_value: self.class.resumo(@title, @starts_at))
    @lead.lead_tasks.create!(account: @lead.account, user: @user, title: task_title.truncate(255), kind: 'meeting', due_at: @starts_at)
    advance_stage
    Ramon::Papeis.atribuir_closer!(@lead)
    confirmation_draft
    enqueue_reminders
    self.class.notify(@lead, 'ramon_meeting_scheduled', @starts_at, @title)
    @lead
  end

  private

  # Nunca regride: quem já está em Negociação e remarcou fica onde está.
  def advance_stage
    stage = @lead.account.lead_stages.find_by(label: STAGE_LABEL)
    return if stage.blank? || @lead.lead_stage.position >= stage.position

    @lead.update!(lead_stage: stage)
  end

  # Rascunho de confirmação (gatilho do compromisso) — estático, sem LLM.
  def confirmation_draft
    first = @lead.name.to_s.split.first.presence || 'cliente'
    @lead.lead_notes.create!(account: @lead.account, body: <<~NOTA.strip.truncate(1000))
      RASCUNHO (revisar antes de enviar) — confirmação de reunião:
      "Oi #{first}! Nossa conversa está confirmada pra #{self.class.quando(@starts_at)}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."
    NOTA
  end

  # Lembretes anti no-show: só offsets ainda no futuro; cancel/reschedule não
  # desagenda — o guard do job mata o lembrete órfão.
  def enqueue_reminders
    Ramon::MeetingReminderJob::OFFSETS.each do |offset, label|
      fire_at = @starts_at - offset
      next if fire_at.past?

      Ramon::MeetingReminderJob.set(wait_until: fire_at).perform_later(@lead.id, @starts_at.iso8601, label)
    end
  end
end
