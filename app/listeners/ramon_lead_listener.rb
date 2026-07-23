# frozen_string_literal: true

class RamonLeadListener < BaseListener
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    return unless conversation.inbox&.auto_create_lead?

    contact = conversation.contact
    return if contact.blank?

    lead = account.leads.open.find_by(contact_id: contact.id)
    if lead
      lead.update!(conversation_id: conversation.id)
    else
      account.leads.create!(
        name: contact.name.presence || contact.phone_number || contact.identifier,
        lead_stage: account.lead_stages.order(:position).first,
        contact_id: contact.id,
        conversation_id: conversation.id
      )
    end
    enqueue_first_response_sla(conversation)
  end

  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    return if lead.blank?

    apply_meta_referral(lead, message)
  end

  def lead_created(event)
    Ramon::StageLabelSync.apply_to_conversation(event.data[:lead])
  end

  def lead_updated(event)
    Ramon::StageLabelSync.apply_to_conversation(event.data[:lead])
  end

  def conversation_updated(event)
    conversation = event.data[:conversation]
    changes = event.data[:changed_attributes]
    return if changes.blank?

    label_change = changes['label_list'] || changes[:label_list]
    return if label_change.blank?

    old_labels, new_labels = label_change
    added = Array(new_labels) - Array(old_labels)
    Ramon::StageLabelSync.apply_to_lead(conversation, added)
  end

  private

  # SLA de 1ª resposta (mapa comercial): o vigia dispara N min depois e só
  # apita se a conversa seguir aberta e sem resposta.
  def enqueue_first_response_sla(conversation)
    minutes = ENV.fetch('RAMON_SLA_FIRST_RESPONSE_MINUTES', '15').to_i
    Ramon::FirstResponseSlaJob.set(wait: minutes.minutes).perform_later(conversation.id)
  end

  # Atribuição: o referral da Meta (click-to-WhatsApp) chega na primeira
  # mensagem, depois do conversation_created — por isso o hook é aqui.
  def apply_meta_referral(lead, message)
    referral = message.content_attributes.with_indifferent_access[:referral]
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
end
