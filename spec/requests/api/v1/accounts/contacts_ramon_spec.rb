require 'rails_helper'

# Campos de pessoa do fork no CRUD nativo de contatos.
RSpec.describe 'Contacts API (campos ramon)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }

  it 'atualiza cpf, data de nascimento e sexo' do
    put "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
        params: { cpf: '529.982.247-25', data_nascimento: '1970-03-15', sexo: 'F' },
        headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    contact.reload
    expect(contact.cpf).to eq('52998224725')
    expect(contact.data_nascimento).to eq(Date.new(1970, 3, 15))
    expect(contact.sexo).to eq('F')
  end

  it 'rejeita cpf inválido com 422' do
    put "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
        params: { cpf: '123' },
        headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.reload.cpf).to be_nil
  end

  it 'expõe os campos da pessoa no payload do lead' do
    contact.update!(cpf: '52998224725', data_nascimento: '1970-03-15', sexo: 'F')
    lead = create(:lead, account: account, contact: contact,
                         lead_stage: account.lead_stages.order(:position).first)
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}", headers: admin.create_new_auth_token
    body = response.parsed_body
    expect(body['contact_cpf']).to eq('52998224725')
    expect(body['contact_data_nascimento']).to eq('1970-03-15')
    expect(body['contact_sexo']).to eq('F')
  end
end
