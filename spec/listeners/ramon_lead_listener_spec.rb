# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RamonLeadListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:event) { Events::Base.new('conversation.created', Time.zone.now, conversation: conversation) }

  it 'cria um lead na etapa Novo linkado ao contato/conversa' do
    expect { listener.conversation_created(event) }.to change { account.leads.count }.by(1)
    lead = account.leads.last
    expect(lead.contact_id).to eq(contact.id)
    expect(lead.conversation_id).to eq(conversation.id)
    expect(lead.lead_stage).to eq(account.lead_stages.find_by(name: 'Novo'))
  end

  it 'não cria se a inbox não tem auto_create_lead' do
    inbox.update!(auto_create_lead: false)
    expect { listener.conversation_created(event) }.not_to(change { account.leads.count })
  end

  it 're-aponta a conversa do lead existente (dedup por contato)' do
    first = create(:conversation, account: account, inbox: inbox, contact: contact)
    listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: first))
    expect { listener.conversation_created(event) }.not_to(change { account.leads.count })
    expect(account.leads.last.conversation_id).to eq(conversation.id)
  end
end
