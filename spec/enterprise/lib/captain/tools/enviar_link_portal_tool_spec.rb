require 'rails_helper'

RSpec.describe Captain::Tools::EnviarLinkPortalTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Jose') }

  it 'gera o token na primeira vez e devolve o link' do
    with_modified_env FRONTEND_URL: 'https://chat.exemplo.br' do
      out = tool.perform(tool_context, lead_id: lead.id.to_s)
      expect(lead.reload.portal_token).to be_present
      expect(out).to include("https://chat.exemplo.br/portal/#{lead.portal_token}")
    end
  end

  it 'reusa o token existente' do
    lead.update!(portal_token: 'abc123')
    expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('/portal/abc123')
  end

  it 'sem FRONTEND_URL avisa que o link nao esta disponivel' do
    with_modified_env FRONTEND_URL: '' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('nao esta configurado')
    end
  end
end
