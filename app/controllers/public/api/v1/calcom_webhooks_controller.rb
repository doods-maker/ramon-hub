class Public::Api::V1::CalcomWebhooksController < PublicController
  TASK_TITLE_PREFIX = 'Reunião Cal.com'.freeze

  # ponytail: janela de dedup no cache Redis já existente — sem tabela nova. Um
  # corpo validamente assinado só é processado 1x por 24h; cobre replay (o mesmo
  # POST reenviado) e a entrega at-least-once do Cal.com. Ceiling: replay após a
  # janela passa — se precisar de garantia permanente, persistir o uid do booking.
  REPLAY_TTL = 24.hours

  before_action :verify_signature
  before_action :reject_replay

  def create
    status = case params[:triggerEvent]
             when 'BOOKING_CREATED' then handle_created
             when 'BOOKING_CANCELLED' then handle_cancelled
             when 'BOOKING_RESCHEDULED' then handle_rescheduled
             else :ok
             end
    head status
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private

  def verify_signature
    secret = ENV.fetch('CALCOM_WEBHOOK_SECRET', nil)
    return head :unauthorized if secret.blank? || account.blank?

    provided = request.headers['X-Cal-Signature-256'].to_s
    expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, request.raw_post)
    return if ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end

  # A assinatura é HMAC do corpo cru → chave única por corpo distinto.
  def reject_replay
    signature = request.headers['X-Cal-Signature-256'].to_s
    key = "ramon:calcom:seen:#{signature}"
    return head :ok unless Rails.cache.write(key, true, unless_exist: true, expires_in: REPLAY_TTL)
  end

  # Mesma conta única do endpoint de leads das LPs.
  def account
    @account ||= Account.find_by(id: ENV.fetch('RAMON_LEAD_CAPTURE_ACCOUNT_ID', nil))
  end

  def handle_created
    return :unprocessable_entity if start_at.blank?

    register_meeting(matched_or_created_lead)
    :created
  end

  def handle_cancelled
    lead = open_lead_for(matched_contact)
    return :ok if lead.blank?

    purge_calcom_tasks(lead, due_at: start_at)
    lead.lead_activities.create!(account: account, kind: 'meeting_cancelled', to_value: meeting_summary)
    notify(lead, 'ramon_meeting_cancelled')
    :ok
  end

  def handle_rescheduled
    return :unprocessable_entity if start_at.blank?

    # ponytail: sem persistir o uid do booking não dá pra achar o horário
    # antigo — apaga as reuniões Cal.com abertas do lead e cria a nova; se um
    # lead precisar de várias reuniões simultâneas, gravar o uid na task.
    lead = matched_or_created_lead
    purge_calcom_tasks(lead)
    register_meeting(lead)
    :ok
  end

  # Mesmo efeito da reunião marcada pelo painel (Ramon::ReuniaoAgendamento);
  # o prefixo no título é o que o cancel/reschedule usam pra achar a tarefa.
  def register_meeting(lead)
    Ramon::ReuniaoAgendamento.call(lead: lead, starts_at: start_at, title: event_title,
                                   task_title: "#{TASK_TITLE_PREFIX}: #{event_title}")
  end

  def notify(lead, type)
    Ramon::ReuniaoAgendamento.notify(lead, type, start_at, event_title)
  end

  # Nome do tipo de evento ("Primeiro Atendimento"), não o título do booking
  # ("Primeiro Atendimento between X and Y") que o Cal.com monta.
  def event_title
    booking[:eventTitle].presence || booking.dig(:eventType, :title).presence ||
      booking[:title].to_s.sub(/ between .*\z/, '')
  end

  def purge_calcom_tasks(lead, due_at: nil)
    tasks = lead.lead_tasks.open_tasks.where(kind: 'meeting').where('title LIKE ?', "#{TASK_TITLE_PREFIX}%")
    tasks = tasks.where(due_at: due_at) if due_at.present?
    tasks.destroy_all
  end

  def meeting_summary
    Ramon::ReuniaoAgendamento.resumo(event_title, start_at)
  end

  def booking
    params[:payload] || {}
  end

  def start_at
    @start_at ||= begin
      Time.zone.parse(booking[:startTime].to_s)
    rescue ArgumentError
      nil
    end
  end

  def attendee
    booking[:attendees]&.first || {}
  end

  def attendee_phone
    raw = booking.dig(:responses, :phone, :value).presence ||
          booking.dig(:responses, :attendeePhoneNumber, :value).presence ||
          attendee[:phoneNumber]
    normalize_phone(raw)
  end

  def attendee_email
    attendee[:email].to_s.downcase.presence
  end

  def normalize_phone(raw)
    digits = raw.to_s.gsub(/\D/, '')
    return "+#{digits}" if [12, 13].include?(digits.length) && digits.start_with?('55')
    return "+55#{digits}" if [10, 11].include?(digits.length)

    nil
  end

  def matched_contact
    @matched_contact ||= find_contact_by_phone || find_contact_by_email
  end

  def find_contact_by_phone
    attendee_phone && account.contacts.find_by(phone_number: attendee_phone)
  end

  def find_contact_by_email
    attendee_email && account.contacts.from_email(attendee_email)
  end

  def open_lead_for(contact)
    contact && account.leads.open.find_by(contact_id: contact.id)
  end

  # Sem match não se perde agendamento: cria contact + lead (como o endpoint
  # das LPs) e notifica no sino via LeadNotificationBuilder.
  def matched_or_created_lead
    contact = matched_contact || create_contact
    open_lead_for(contact) || create_lead(contact)
  end

  def create_contact
    account.contacts.create!(
      name: attendee[:name].to_s.strip.presence || attendee_email || attendee_phone,
      email: attendee_email,
      phone_number: attendee_phone
    )
  end

  def create_lead(contact)
    lead = account.leads.create!(
      name: contact.name,
      lead_stage: account.lead_stages.order(:position).first,
      contact_id: contact.id,
      source: 'calcom-agenda'
    )
    Ramon::LeadNotificationBuilder.new(lead: lead).perform
    lead
  end
end
