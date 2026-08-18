# Lembrete anti no-show (mapa comercial 23/07): agendado via set(wait_until:)
# pelo webhook do Cal.com. Cancel/reschedule não desagenda nada — o guard da
# tarefa aberta mata o lembrete órfão (mesmo padrão do controller: recompute).
class Ramon::MeetingReminderJob < ApplicationJob
  queue_as :low

  # offset → label pt-BR do push
  OFFSETS = {
    24.hours => '24h antes',
    8.hours => '8h antes',
    1.hour => '1h antes',
    30.minutes => '30min antes',
    5.minutes => '5min antes'
  }.freeze

  TOLERANCE = 60.seconds
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def perform(lead_id, start_at_iso, label)
    lead = Lead.find_by(id: lead_id)
    start_at = Time.zone.parse(start_at_iso)
    unless lead && meeting_open?(lead, start_at)
      return Rails.logger.info("MeetingReminderJob: lead #{lead_id} sem reunião aberta em #{start_at_iso} — lembrete órfão descartado")
    end
    # dedup: reschedule ida-e-volta re-enfileira os mesmos offsets — só o 1º apita
    return unless Rails.cache.write("ramon:reminder:#{lead_id}:#{start_at_iso}:#{label}", true, unless_exist: true, expires_in: 25.hours)

    hora = start_at.in_time_zone(TIME_ZONE).strftime('%d/%m %H:%M')
    # sino do hub (todo usuário da conta) — o ntfy é opcional, o hub não
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_meeting_reminder',
                                       meta: { 'quando' => hora, 'label' => label }).perform
    return if ENV.fetch('NTFY_TOPIC', nil).blank?

    # timing já resolvido pelo wait_until — push direto, sem re-enfileirar
    Ramon::NtfyPushJob.perform_now(lead_id, title: "Reunião #{lead.name} em #{label}",
                                            body: "#{hora} — hora de mandar a mensagem de confirmação pro cliente")
  end

  private

  def meeting_open?(lead, start_at)
    return false if start_at.blank?

    lead.lead_tasks.open_tasks.exists?(kind: 'meeting', due_at: (start_at - TOLERANCE)..(start_at + TOLERANCE))
  end
end
