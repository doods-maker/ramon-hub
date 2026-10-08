# frozen_string_literal: true

# Criar lead da conversa e origem do lead — o código de sempre, que morava no RamonLeadListener (mudou de arquivo na
# B5-leads, sem mudar nada). Quem chama: o ouvinte (código no comando, ou a reserva) e as rotinas prontas criar_lead /
# origem_do_lead (Ramon::Fluxos::Rotinas::Leads), quando o fluxo migrado está no comando.
module Ramon::LeadDaConversa
  module_function

  # Só caixas com "Criar lead" ligado e conversa com contato.
  def cabe?(conversation) = conversation.inbox&.auto_create_lead? && conversation.contact.present?

  # Liga a conversa ao lead aberto do mesmo contato (pessoa ≠ caso: lead fechado não conta) ou cria o lead na 1ª etapa.
  def criar_ou_ligar(conversation)
    account = conversation.account
    contact = conversation.contact
    lead = account.leads.open.find_by(contact_id: contact.id)
    return lead.tap { |l| l.update!(conversation_id: conversation.id) } if lead

    account.leads.create!(
      name: contact.name.presence || contact.phone_number || contact.identifier,
      lead_stage: account.lead_stages.order(:position).first,
      contact_id: contact.id,
      conversation_id: conversation.id
    )
  end

  # Há o que anotar? Anúncio da Meta na mensagem, ou canal ainda não derivado ('outro'). Sem isso o código não faz nada —
  # e o fluxo de origem nem começa (1 execução por lead, não por mensagem).
  def origem_pendente?(lead, message) = referral_da(message).present? || lead.channel == 'outro'

  def origem(lead, message)
    apply_meta_referral(lead, message)
    derive_channel_from_first_contact(lead, message)
  end

  def referral_da(message) = message.content_attributes.with_indifferent_access[:referral]

  # Atribuição: o referral da Meta (click-to-WhatsApp) chega na primeira mensagem, depois do conversation_created.
  def apply_meta_referral(lead, message)
    referral = referral_da(message)
    return if referral.blank?

    meta = referral.slice('source_id', 'source_type', 'source_url', 'headline', 'ctwa_clid').compact_blank
    attrs = { custom_attributes: lead.custom_attributes.merge('meta_referral' => meta) }
    if lead.source.blank?
      attrs[:source] = referral_source_label(referral)
      attrs[:channel] = 'meta_ads'
    end
    lead.update!(attrs)
  end

  def referral_source_label(referral)
    detail = referral['source_id'].presence || referral['headline'].presence
    ['anuncio-meta', detail].compact.join(': ').truncate(255)
  end

  # Regra de negócio (13/08, design funil-estrategico): nos números da banca, quem chega sem anúncio e sem assinatura de
  # site/LP/bio veio por indicação. 'outro' é o sentinela de "não derivado" — canal manual ou já derivado (landing_page,
  # meta_ads) nunca é sobrescrito.
  def derive_channel_from_first_contact(lead, message)
    return unless lead.channel == 'outro'

    channel, source = Ramon::SourceCatalog.derive_from_message(message.content)
    channel ||= message.inbox&.channel_type == 'Channel::Instagram' ? 'instagram' : 'indicacao'
    attrs = { channel: channel }
    attrs[:source] = source if source.present? && lead.source.blank?
    lead.update!(attrs)
  end
end
