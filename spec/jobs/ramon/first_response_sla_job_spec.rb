require 'rails_helper'

RSpec.describe Ramon::FirstResponseSlaJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:lead) { create(:lead, account: account, conversation_id: conversation.id, name: 'Maria da Silva') }

  before { allow(Ramon::NtfyPushJob).to receive(:perform_now) }

  # 13:00 UTC = 10:00 America/Sao_Paulo — horário comercial (bloco = travel_back automático)
  it 'apita quando a conversa segue aberta e sem 1ª resposta, em horário comercial' do
    travel_to Time.zone.parse('2026-07-23 13:00:00 UTC') do
      described_class.perform_now(conversation.id)
    end

    expect(Ramon::NtfyPushJob).to have_received(:perform_now)
      .with(lead.id, title: 'Lead aguardando 1a resposta', body: include('Maria da Silva'))
  end

  it 'não apita se a 1ª resposta já saiu' do
    conversation.update!(first_reply_created_at: Time.current)

    travel_to Time.zone.parse('2026-07-23 13:00:00 UTC') do
      described_class.perform_now(conversation.id)
    end

    expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
  end

  it 'não apita com a conversa resolvida' do
    conversation.update!(status: :resolved)

    travel_to Time.zone.parse('2026-07-23 13:00:00 UTC') do
      described_class.perform_now(conversation.id)
    end

    expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
  end

  # 01:00 UTC = 22:00 America/Sao_Paulo — fora do 07–21, o /bom-dia cobre a manhã
  it 'fora do horário 07–21 de São Paulo é no-op' do
    travel_to Time.zone.parse('2026-07-24 01:00:00 UTC') do
      described_class.perform_now(conversation.id)
    end

    expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
  end

  it 'conversa sem lead vinculado é no-op' do
    lead.update!(conversation_id: nil)

    travel_to Time.zone.parse('2026-07-23 13:00:00 UTC') do
      described_class.perform_now(conversation.id)
    end

    expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
  end
end
