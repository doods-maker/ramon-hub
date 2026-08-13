class Public::Api::V1::RamonLeadsController < PublicController
  before_action :verify_capture_token

  def create
    return head :ok if params[:website].present?

    phone = normalized_phone
    return head :unprocessable_entity if phone.blank?

    contact = find_or_create_contact(phone)
    record_marketing_consent(contact) if consent_given?
    register_lead(contact, phone)

    head :created
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private

  def register_lead(contact, phone)
    lead = open_lead_for(contact)
    if lead
      # Lead ainda vivo no funil → não duplica: registra atividade na Linha da Vida.
      lead.lead_activities.create!(account: account, kind: 'lp_recaptured', to_value: recapture_source)
      # Triagem nova vale registrar; a etapa NÃO anda sozinha (um lead em
      # Negociação não pode regredir porque refez o quiz).
      lead.update!(custom_attributes: lead.custom_attributes.merge(quiz_attributes)) if quiz_attributes.present?
    else
      lead = create_lead(contact, phone)
    end
    lead.lead_notes.create!(account: account, body: params[:mensagem].to_s.truncate(1000)) if params[:mensagem].present?
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
    account.leads.open.find_by(contact_id: contact.id)
  end

  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_content].freeze

  def create_lead(contact, phone)
    account.leads.create!(
      name: params[:nome].to_s.strip.presence || phone,
      lead_stage: initial_stage,
      contact_id: contact.id,
      source: params[:campanha].to_s.presence,
      channel: 'landing_page',
      custom_attributes: utm_attributes.merge(quiz_attributes)
    )
  end

  def utm_attributes
    utm = UTM_KEYS.index_with { |key| params[key].to_s.strip.first(255).presence }.compact
    utm.present? ? { 'utm' => utm } : {}
  end

  # Lead qualificado pelo quiz nasce em Qualificação (design 13/08, decisão 4):
  # o SDR confirma com documento — não recomeça do "chegou alguém".
  def initial_stage
    (quiz_qualificado? && account.lead_stages.find_by(label: 'fase-qualificacao')) ||
      account.lead_stages.order(:position).first
  end

  def quiz_qualificado?
    quiz_attributes.dig('quiz', 'qualificado') == true
  end

  QUIZ_RESPOSTA_KEYS = %i[id pergunta resposta valor reprova duvida].freeze

  def quiz_attributes
    @quiz_attributes ||= begin
      respostas = quiz_respostas
      respostas.empty? ? {} : { 'quiz' => quiz_payload(respostas) }
    end
  end

  def quiz_respostas
    Array.wrap(params[:respostas]).first(20).filter_map do |r|
      r.permit(*QUIZ_RESPOSTA_KEYS).to_h.compact_blank if r.respond_to?(:permit)
    end
  end

  def quiz_payload(respostas)
    {
      'qualificado' => ActiveModel::Type::Boolean.new.cast(params[:qualificado]) == true,
      'duvidas' => Array.wrap(params[:duvidas]).map { |d| d.to_s.first(120) }.first(10),
      'respostas' => respostas,
      'em' => Time.current.iso8601
    }
  end

  # Consentimento LGPD de marketing (item 20 do plano mestre).
  # O form da LP manda o campo opcional `consent` (checkbox: "true"/"1"/"on").
  # Só CONCEDE por aqui — revogação é manual no painel do lead.
  def consent_given?
    params[:consent].present? && ActiveModel::Type::Boolean.new.cast(params[:consent])
  end

  def record_marketing_consent(contact)
    contact.update!(custom_attributes: contact.custom_attributes.merge(
      'consent_marketing' => {
        'granted' => true,
        'at' => Time.current.iso8601,
        'source' => "lp:#{params[:campanha].to_s.strip.presence || params[:utm_campaign].to_s.strip.presence || 'desconhecida'}"
      }
    ))
  end

  def recapture_source
    (params[:campanha].presence || utm_attributes.dig('utm', 'utm_campaign') || 'desconhecida').to_s.truncate(255)
  end
end
