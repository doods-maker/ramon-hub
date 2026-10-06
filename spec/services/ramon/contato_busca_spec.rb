require 'rails_helper'

RSpec.describe Ramon::ContatoBusca do
  let(:account) { create(:account) }
  let!(:por_cpf) { create(:contact, account: account, cpf: '52998224725') }
  let!(:sem_nove) { create(:contact, account: account, phone_number: '+554891203381') }

  def buscar(termo)
    described_class.por_numero(account.contacts, termo)
  end

  it 'acha pelo CPF com ou sem máscara' do
    expect(buscar('529.982.247-25')).to contain_exactly(por_cpf)
  end

  it 'acha o celular gravado sem o 9 digitando com 9 e sem o 55' do
    expect(buscar('(48) 99120-3381')).to contain_exactly(sem_nove)
  end

  it 'termo com menos de 10 dígitos não busca por número' do
    expect(buscar('Maria 3381')).to be_nil
  end

  describe 'na busca de contatos da API', type: :request do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'devolve o contato achado pelo CPF', :aggregate_failures do
      get "/api/v1/accounts/#{account.id}/contacts/search",
          params: { q: '529.982.247-25' },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([por_cpf.id])
    end
  end
end
