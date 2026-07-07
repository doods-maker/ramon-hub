require 'rails_helper'

RSpec.describe 'Linha da Vida API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) do
    create(:contact, account: account, name: 'Maria', cpf: '52998224725',
                     data_nascimento: Date.new(1970, 3, 15), sexo: 'F')
  end

  it 'devolve pessoa, casos e marcos etários' do
    won_stage = account.lead_stages.find_by(is_won: true)
    open_stage = account.lead_stages.order(:position).first
    caso = create(:lead, account: account, contact: contact, lead_stage: won_stage, name: 'Caso antigo')
    interesse = create(:lead, account: account, contact: contact, lead_stage: open_stage, name: 'Interesse novo')

    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/linha_da_vida",
        headers: agent.create_new_auth_token

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['contact']['cpf']).to eq('52998224725')
    expect(body['leads'].pluck('id')).to contain_exactly(caso.id, interesse.id)
    expect(body['leads'].find { |l| l['id'] == caso.id }['is_won']).to be(true)
    expect(body['marcos'].pluck('key')).to include('aposentadoria_idade_urbana')
  end

  it '404 para contato de outra conta' do
    estranho = create(:contact, account: create(:account))
    get "/api/v1/accounts/#{account.id}/contacts/#{estranho.id}/linha_da_vida",
        headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
