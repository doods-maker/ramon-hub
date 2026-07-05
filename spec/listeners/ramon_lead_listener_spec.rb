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

  describe '#message_created -> atribuição do referral da Meta' do
    let(:lead) do
      create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                    conversation: conversation, contact: contact)
    end
    let(:referral) do
      { 'source_id' => '12034', 'source_type' => 'ad', 'source_url' => 'https://fb.me/xyz',
        'headline' => 'Machucou no trabalho?', 'ctwa_clid' => 'clid-abc' }
    end
    let(:message) do
      create(:message, account: account, conversation: conversation, message_type: :incoming,
                       content: 'oi', content_attributes: { referral: referral })
    end

    it 'grava source e meta_referral (com ctwa_clid) no lead' do
      lead
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
      lead.reload
      expect(lead.source).to eq('anuncio-meta: 12034')
      expect(lead.custom_attributes['meta_referral']).to include('ctwa_clid' => 'clid-abc', 'source_id' => '12034')
    end

    it 'não sobrescreve source já preenchido, mas guarda o referral' do
      lead.update!(source: 'bpc-loas')
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
      lead.reload
      expect(lead.source).to eq('bpc-loas')
      expect(lead.custom_attributes['meta_referral']).to include('ctwa_clid' => 'clid-abc')
    end

    it 'ignora mensagem sem referral' do
      lead
      plain = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
      expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: plain)) }
        .not_to(change { lead.reload.custom_attributes })
    end
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
