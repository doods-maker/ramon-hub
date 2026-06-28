# frozen_string_literal: true

class RamonLeadListener < BaseListener
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    return unless conversation.inbox&.auto_create_lead?

    contact = conversation.contact
    return if contact.blank?

    lead = account.leads.find_by(contact_id: contact.id)
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
  end
end
