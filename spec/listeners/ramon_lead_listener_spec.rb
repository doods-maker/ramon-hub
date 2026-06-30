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

  describe '#lead_updated -> etiqueta a conversa' do
    it 'aplica a fase-* da etapa do lead na conversa' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      lead.update!(lead_stage: account.lead_stages.find_by(label: 'fase-qualificacao'))
      ev = Events::Base.new('lead.updated', Time.zone.now, lead: lead)
      listener.lead_updated(ev)
      expect(conversation.reload.label_list).to contain_exactly('fase-qualificacao')
    end
  end

  describe '#conversation_updated -> move o lead' do
    it 'move o lead pra etapa da fase-* adicionada' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      ev = Events::Base.new('conversation.updated', Time.zone.now,
                            conversation: conversation,
                            changed_attributes: { 'label_list' => [[], ['fase-qualificacao']] })
      listener.conversation_updated(ev)
      expect(lead.reload.lead_stage).to eq(account.lead_stages.find_by(label: 'fase-qualificacao'))
    end

    it 'ignora quando label_list não mudou' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      ev = Events::Base.new('conversation.updated', Time.zone.now,
                            conversation: conversation,
                            changed_attributes: { 'status' => %w[open resolved] })
      expect { listener.conversation_updated(ev) }.not_to(change { lead.reload.lead_stage_id })
    end
  end
end
