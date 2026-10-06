require 'rails_helper'

RSpec.describe RamonConversa do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account) }
  let(:stage) { create(:lead_stage, account: account, name: 'Reunião marcada', color: '#6D28D9') }
  let(:thesis) { create(:thesis, account: account, name: 'Auxílio-acidente') }
  let(:sdr) { create(:user, account: account, name: 'Camila') }

  it 'sem lead, o bloco do lead é nil' do
    expect(conversation.ramon_lead_slim).to be_nil
  end

  it 'expõe etapa, cor, tese e SDR do lead da conversa' do
    create(:lead, account: account, conversation: conversation, lead_stage: stage, thesis: thesis, sdr: sdr)
    expect(conversation.reload.ramon_lead_slim).to include(
      stage_name: 'Reunião marcada', stage_color: '#6D28D9', thesis_name: 'Auxílio-acidente', sdr_name: 'Camila', closer_name: nil
    )
  end

  it 'vai no evento do websocket' do
    create(:lead, account: account, conversation: conversation, lead_stage: stage)
    expect(Conversations::EventDataPresenter.new(conversation.reload).push_data[:ramon_lead]).to include(stage_name: 'Reunião marcada')
  end

  describe 'na lista de conversas da API', type: :request do
    let(:agent) { create(:user, account: account, role: :administrator) }

    it 'devolve o lead enxuto de cada conversa' do
      create(:lead, account: account, conversation: conversation, lead_stage: stage, thesis: thesis)
      get "/api/v1/accounts/#{account.id}/conversations",
          params: { assignee_type: 'all' },
          headers: agent.create_new_auth_token,
          as: :json

      payload = response.parsed_body.dig('data', 'payload').first
      expect(payload['ramon_lead']).to include('stage_name' => 'Reunião marcada', 'thesis_name' => 'Auxílio-acidente')
    end
  end
end
