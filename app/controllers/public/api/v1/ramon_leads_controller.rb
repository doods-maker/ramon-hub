class Public::Api::V1::RamonLeadsController < PublicController
  before_action :verify_capture_token

  def create
    return head :ok if params[:website].present?

    phone = normalized_phone
    return head :unprocessable_entity if phone.blank?

    contact = find_or_create_contact(phone)
    register_lead(contact, phone)

    head :created
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private

  def register_lead(contact, phone)
    lead = open_lead_for(contact)
    if lead
      lead.lead_notes.create!(account: account, body: recapture_note_body)
    else
      lead = create_lead(contact, phone)
      lead.lead_notes.create!(account: account, body: params[:mensagem].to_s.truncate(1000)) if params[:mensagem].present?
    end
    Ramon::LeadNotificationBuilder.new(lead: lead).perform
    lead
  end

  def verify_capture_token
    expected = ENV.fetch('RAMON_LEAD_CAPTURE_TOKEN', nil)
    return head :unauthorized if expected.blank? || account.blank?

    provided = request.headers['X-Capture-Token'].presence || params[:capture_token].to_s
    return if ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end

  def account
    @account ||= Account.find_by(id: ENV.fetch('RAMON_LEAD_CAPTURE_ACCOUNT_ID', nil))
  end

  def normalized_phone
    digits = params[:telefone].to_s.gsub(/\D/, '')
    return unless [12, 13].include?(digits.length) && digits.start_with?('55')

    "+#{digits}"
  end

  def find_or_create_contact(phone)
    account.contacts.find_by(phone_number: phone) ||
      account.contacts.create!(name: params[:nome].to_s.strip.presence || phone, phone_number: phone)
  end

  def open_lead_for(contact)
    account.leads
           .joins(:lead_stage)
           .where(contact_id: contact.id, lead_stages: { is_won: false, is_lost: false })
           .first
  end

  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_content].freeze

  def create_lead(contact, phone)
    account.leads.create!(
      name: params[:nome].to_s.strip.presence || phone,
      lead_stage: account.lead_stages.order(:position).first,
      contact_id: contact.id,
      source: params[:campanha].to_s.presence,
      channel: 'landing_page',
      custom_attributes: utm_attributes
    )
  end

  def utm_attributes
    utm = UTM_KEYS.index_with { |key| params[key].to_s.strip.first(255).presence }.compact
    utm.present? ? { 'utm' => utm } : {}
  end

  def recapture_note_body
    body = "Novo envio pela landing page (campanha: #{params[:campanha].presence || 'desconhecida'})."
    body += " Mensagem: #{params[:mensagem]}" if params[:mensagem].present?
    body.truncate(1000)
  end
end
