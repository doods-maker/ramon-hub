require 'rails_helper'

RSpec.describe Ramon::AgenteNotifyJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, private: true, content: '@claude oi') }

  it 'faz POST no runner com o segredo' do
    with_modified_env(RAMON_AGENTE_RUNNER_URL: 'http://runner/hub', RAMON_AGENTE_SECRET: 's3') do
      stub = stub_request(:post, 'http://runner/hub').with(headers: { 'X-Agente-Secret' => 's3' }).to_return(status: 202)
      described_class.perform_now(message.id)
      expect(stub).to have_been_requested
    end
  end
end
