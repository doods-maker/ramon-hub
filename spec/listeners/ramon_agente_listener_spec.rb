# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RamonAgenteListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:eduardo) { create(:user, account: account, email: 'edu@x.com') }
  let(:conversation) { create(:conversation, account: account) }

  def event_for(message)
    Events::Base.new('message.created', Time.zone.now, message: message)
  end

  around { |ex| with_modified_env(RAMON_AGENTE_RUNNER_URL: 'http://runner/hub', RAMON_AGENTE_EDUARDO_EMAIL: 'edu@x.com') { ex.run } }

  it 'enfileira quando é nota privada @claude do Eduardo' do
    msg = create(:message, account: account, conversation: conversation, private: true, sender: eduardo, content: '@claude resume')
    expect { listener.message_created(event_for(msg)) }.to have_enqueued_job(Ramon::AgenteNotifyJob).with(msg.id)
  end

  it 'ignora nota pública, sem @claude ou de outro usuário' do
    outro = create(:user, account: account, email: 'o@x.com')
    m1 = create(:message, account: account, conversation: conversation, private: false, sender: eduardo, content: '@claude x')
    m2 = create(:message, account: account, conversation: conversation, private: true, sender: eduardo, content: 'oi')
    m3 = create(:message, account: account, conversation: conversation, private: true, sender: outro, content: '@claude x')
    [m1, m2, m3].each { |m| expect { listener.message_created(event_for(m)) }.not_to have_enqueued_job(Ramon::AgenteNotifyJob) }
  end
end
