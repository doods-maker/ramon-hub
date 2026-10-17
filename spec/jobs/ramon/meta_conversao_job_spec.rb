# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::MetaConversaoJob do
  let(:account) { create(:account) }
  let(:canal) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'tok', 'phone_number_id' => 'p1', 'business_account_id' => 'w-conversa' })
  end
  let(:referral) { { 'ctwa_clid' => 'clid-1', 'inbox_id' => canal.inbox.id } }
  let(:lead) { create(:lead, account: account, custom_attributes: { 'meta_referral' => referral }) }
  let(:evento) do
    MetaEvento.create!(account: account, lead: lead, evento: 'QualifiedLead', event_id: "lead-#{lead.id}-QualifiedLead",
                       ocorrido_em: Time.zone.now)
  end
  let(:cliente) { instance_double(Ramon::MetaCapi::Cliente) }

  before do
    allow(Ramon::MetaCapi::Cliente).to receive(:new).and_return(cliente)
  end

  it 'envia e marca enviado' do
    allow(cliente).to receive(:enviar).and_return(true)
    lead.update!(custom_attributes: { 'meta_referral' => referral.merge('waba_id' => 'w1') })
    described_class.perform_now(evento.id)
    expect(evento.reload).to have_attributes(status: 'enviado')
    expect(evento.enviado_em).to be_present
  end

  it 'sem caixa do clique usa WABA e token do canal da conversa' do
    outro = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                      provider_config: { 'api_key' => 'tok2', 'phone_number_id' => 'p2', 'business_account_id' => 'w-outro' })
    lead.update!(custom_attributes: { 'meta_referral' => { 'ctwa_clid' => 'clid-1', 'inbox_id' => 0 } },
                 conversation: create(:conversation, account: account, inbox: outro.inbox))
    allow(cliente).to receive(:enviar).and_return(true)
    described_class.perform_now(evento.id)
    expect(Ramon::MetaCapi::Cliente).to have_received(:new).with(token: 'tok2', waba_id: 'w-outro')
  end

  it 'caixa do clique apagada ignora o waba_id do referral e usa WABA e token da conversa' do
    outro = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                      provider_config: { 'api_key' => 'tok2', 'phone_number_id' => 'p2', 'business_account_id' => 'w-outro' })
    lead.update!(custom_attributes: { 'meta_referral' => { 'ctwa_clid' => 'clid-1', 'inbox_id' => 0, 'waba_id' => 'w-clique' } },
                 conversation: create(:conversation, account: account, inbox: outro.inbox))
    allow(cliente).to receive(:enviar).and_return(true)
    described_class.perform_now(evento.id)
    expect(Ramon::MetaCapi::Cliente).to have_received(:new).with(token: 'tok2', waba_id: 'w-outro')
  end

  it 'erro transitório re-enfileira e o evento continua pendente' do
    allow(cliente).to receive(:enviar).and_raise(Ramon::MetaCapi::Transitorio)
    expect { described_class.perform_now(evento.id) }.to have_enqueued_job(described_class).with(evento.id)
    expect(evento.reload.status).to eq('pendente')
  end

  it 'recusa (400) grava erro e não tenta de novo' do
    allow(cliente).to receive(:enviar).and_raise(Ramon::MetaCapi::Recusado.new(400, 100))
    described_class.perform_now(evento.id)
    expect(evento.reload.status).to eq('erro')
    expect(evento.erro).to include('Recusado')
  end

  it 'sem canal marca ignorado' do
    lead.update!(custom_attributes: { 'meta_referral' => { 'ctwa_clid' => 'c', 'inbox_id' => 0 } })
    described_class.perform_now(evento.id)
    expect(evento.reload).to have_attributes(status: 'ignorado', erro: 'sem_waba')
  end
end
