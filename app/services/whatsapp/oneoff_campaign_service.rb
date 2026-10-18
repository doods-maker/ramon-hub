class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  # Ramon fork (LGPD): opt-out de marketing — o cliente responde só "parar"/"sair"/"pare"/"cancelar" ou a Meta recusa o
  # envio com 131050 (a pessoa parou de receber marketing). Revoga consent_marketing; só registra, nada sai pro cliente.
  OPT_OUT = %w[parar sair pare cancelar].freeze

  # Chamado pelo RamonLeadListener: mensagem recebida (palavra) ou envio que falhou (131050).
  def self.opt_out!(message)
    origem = origem_opt_out(message)
    contact = message.conversation.contact
    return if origem.nil? || contact.blank? || contact.custom_attributes&.dig('consent_marketing', 'granted') == false

    contact.update!(custom_attributes: contact.custom_attributes.to_h.merge(
      'consent_marketing' => { 'granted' => false, 'at' => Time.current.iso8601, 'source' => "opt_out:#{origem}" }
    ))
  end

  def self.origem_opt_out(message)
    return 'meta_131050' if message.external_error.to_s.include?('131050')

    'resposta' if message.incoming? && OPT_OUT.include?(I18n.transliterate(message.content.to_s.downcase).delete('^a-z'))
  end
  private_class_method :origem_opt_out

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    raise 'WhatsApp Cloud provider required' if channel.provider != 'whatsapp_cloud'
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
  end

  def extract_audience_labels
    audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: audience_label_ids).pluck(:title)
  end

  def process_contact(contact)
    Rails.logger.info "Processing contact: #{contact.name} (#{contact.phone_number})"

    if contact.phone_number.blank?
      Rails.logger.info "Skipping contact #{contact.name} - no phone number"
      return
    end

    # Ramon fork (LGPD): por padrão a campanha em massa só dispara pra quem tem
    # consentimento de marketing registrado no contato (custom_attributes.consent_marketing).
    # O gestor pode desligar o filtro na campanha (consentimento via contrato/procuração); opt-out vale sempre.
    if sem_consentimento?(contact)
      @skipped_without_consent += 1
      Rails.logger.info "Skipping contact #{contact.name} - no marketing consent (LGPD)"
      return
    end

    if campaign.template_params.blank?
      Rails.logger.error "Skipping contact #{contact.name} - no template_params found for WhatsApp campaign"
      return
    end

    processed_template_params = process_liquid_template_params(contact)
    return if processed_template_params.nil?

    send_whatsapp_template_message(to: contact.phone_number, template_params: processed_template_params)
  end

  def process_audience(audience_labels)
    contacts = campaign.account.contacts.tagged_with(audience_labels, any: true)
    Rails.logger.info "Processing #{contacts.count} contacts for campaign #{campaign.id}"

    @skipped_without_consent = 0
    contacts.each { |contact| process_contact(contact) }

    Rails.logger.info "Campaign #{campaign.id}: #{@skipped_without_consent} contact(s) skipped without marketing consent (LGPD)"
    Rails.logger.info "Campaign #{campaign.id} processing completed"
  end

  # trigger_rules.only_with_marketing_consent: false desliga o filtro; ausente = ligado.
  def consent_filter?
    campaign.trigger_rules&.dig('only_with_marketing_consent') != false
  end

  def marketing_consent_granted?(contact)
    contact.custom_attributes&.dig('consent_marketing', 'granted') == true
  end

  def marketing_opt_out?(contact) = contact.custom_attributes&.dig('consent_marketing', 'granted') == false

  def sem_consentimento?(contact) = !marketing_consent_granted?(contact) && (consent_filter? || marketing_opt_out?(contact))

  def process_liquid_template_params(contact)
    liquid_processor = Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: contact)
    processed_template_params = liquid_processor.process_template_params(campaign.template_params)

    Rails.logger.info "Skipping contact #{contact.name} - liquid variables resolved to blank values" if processed_template_params.nil?

    processed_template_params
  rescue StandardError => e
    Rails.logger.error "Failed to process liquid template params for contact #{contact.name}: #{e.message}"
    nil
  end

  def send_whatsapp_template_message(to:, template_params:)
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params
    )

    name, namespace, lang_code, processed_parameters = processor.call

    return if name.blank?

    channel.send_template(to, {
                            name: name,
                            namespace: namespace,
                            lang_code: lang_code,
                            parameters: processed_parameters
                          }, nil)

  rescue StandardError => e
    Rails.logger.error "Failed to send WhatsApp template message to #{to}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    # continue processing remaining contacts
    nil
  end
end
