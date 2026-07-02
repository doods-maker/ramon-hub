require 'rails_helper'

RSpec.describe Ramon::LeadNotificationBuilder do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account, name: 'Maria da LP') }

  describe '#perform' do
    it 'cria uma notificação ramon_lead_created para cada usuário da conta' do
      expect { described_class.new(lead: lead).perform }.to change(Notification, :count).by(2)
      expect(Notification.pluck(:user_id)).to match_array([admin.id, agent.id])
    end

    it 'aponta o lead como primary_actor e usa o tipo novo' do
      described_class.new(lead: lead).perform
      notification = Notification.first
      expect(notification.notification_type).to eq('ramon_lead_created')
      expect(notification.primary_actor).to eq(lead)
    end

    it 'monta título com o nome do lead' do
      described_class.new(lead: lead).perform
      expect(Notification.first.push_message_title).to include('Maria da LP')
      expect(Notification.first.push_message_body).to include('Maria da LP')
    end
  end
end
