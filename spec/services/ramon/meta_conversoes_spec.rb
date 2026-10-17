# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::MetaConversoes do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:referral) { { 'ctwa_clid' => 'clid-1', 'inbox_id' => 1, 'waba_id' => 'w1' } }
  let(:lead) { create(:lead, account: account, custom_attributes: { 'meta_referral' => referral }) }

  def etapa(label) = account.lead_stages.find_by(label: label)

  def eventos(nome = nil) = MetaEvento.where(lead_id: lead.id).then { |q| nome ? q.where(evento: nome) : q }

  around do |ex|
    with_modified_env(RAMON_META_CAPI: 'on') { ex.run }
  end

  it 'não faz nada com a chave off' do
    with_modified_env(RAMON_META_CAPI: 'off') { lead.update!(lead_stage: etapa('fase-reuniao-agendada')) }
    expect(eventos.count).to eq(0)
  end

  it 'não faz nada sem ctwa_clid' do
    lead.update!(custom_attributes: {})
    lead.update!(lead_stage: etapa('fase-reuniao-agendada'))
    expect(eventos.count).to eq(0)
  end

  it 'avisa QualifiedLead uma única vez, mesmo com o card indo e voltando' do
    expect { lead.update!(lead_stage: etapa('fase-reuniao-agendada')) }.to have_enqueued_job(Ramon::MetaConversaoJob)
    lead.update!(lead_stage: etapa('fase-qualificacao'))
    expect { lead.update!(lead_stage: etapa('fase-reuniao-agendada')) }.not_to have_enqueued_job(Ramon::MetaConversaoJob)
    expect(eventos('QualifiedLead').count).to eq(1)
    expect(eventos('QualifiedLead').first).to have_attributes(status: 'pendente', event_id: "lead-#{lead.id}-QualifiedLead")
  end

  it 'pulando para Reunião realizada avisa só InitiateCheckout' do
    lead.update!(lead_stage: etapa('fase-reuniao-realizada'))
    expect(eventos.pluck(:evento)).to eq(['InitiateCheckout'])
  end

  it 'ganho avisa Purchase' do
    lead.update!(lead_stage: account.lead_stages.find_by(is_won: true), value: 1500)
    expect(eventos.pluck(:evento)).to eq(['Purchase'])
  end
end
