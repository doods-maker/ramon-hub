require 'rails_helper'

RSpec.describe Notification::RemoveDuplicateNotificationJob do
  let(:user) { create(:user) }
  let(:conversation) { create(:conversation) }

  it 'enqueues the job' do
    duplicate_notification = create(:notification, user: user, notification_type: 'conversation_creation', primary_actor: conversation)
    expect do
      described_class.perform_later(duplicate_notification)
    end.to have_enqueued_job(described_class)
      .on_queue('default')
  end

  it 'removes duplicate notifications' do
    create(:notification, user: user, notification_type: 'conversation_creation', primary_actor: conversation)
    duplicate_notification = create(:notification, user: user, notification_type: 'conversation_creation', primary_actor: conversation)

    described_class.perform_now(duplicate_notification)
    expect(Notification.count).to eq(1)
  end

  it 'keeps notifications whose primary actor only shares the id (different type)' do
    create(:notification, user: user, notification_type: 'conversation_creation', primary_actor: conversation)
    chamada = LlmChamada.create!(id: conversation.id, account: conversation.account, funcao: 'copiloto', created_at: Time.current)
    alerta = create(:notification, user: user, notification_type: 'ramon_ia_gasto', primary_actor: chamada)

    described_class.perform_now(alerta)
    expect(Notification.count).to eq(2)
  end
end
