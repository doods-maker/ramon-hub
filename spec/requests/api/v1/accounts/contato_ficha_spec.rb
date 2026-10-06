require 'rails_helper'

# FORK(ramon): a ficha do contato mostra e edita CPF e data de nascimento.
RSpec.describe 'Ficha do contato (CPF e nascimento)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, cpf: '52998224725', data_nascimento: Date.new(1970, 3, 15)) }

  it 'o contato traz CPF e nascimento', :aggregate_failures do
    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}", headers: agent.create_new_auth_token, as: :json

    payload = response.parsed_body['payload']
    expect(payload['cpf']).to eq('52998224725')
    expect(payload['data_nascimento']).to eq('1970-03-15')
  end

  it 'grava CPF com máscara (só os dígitos) e nascimento', :aggregate_failures do
    patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          params: { cpf: '111.444.777-35', data_nascimento: '1980-01-02' },
          headers: agent.create_new_auth_token,
          as: :json

    expect(response).to have_http_status(:success)
    expect(contact.reload.cpf).to eq('11144477735')
    expect(contact.data_nascimento).to eq(Date.new(1980, 1, 2))
  end
end
