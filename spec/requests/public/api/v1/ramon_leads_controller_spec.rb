require 'rails_helper'

RSpec.describe 'Public Ramon Leads API', type: :request do
  let(:account) { create(:account) }
  let!(:stage_novo) { create(:lead_stage, account: account, name: 'Novo', position: 0) }
  let!(:stage_reuniao) { create(:lead_stage, account: account, name: 'Reunião', position: 1) }
  let(:token) { 'tok-secreto' }
  let(:payload) { { nome: 'Maria da Silva', telefone: '5548999887766', campanha: 'auxilio-acidente', mensagem: 'Sofri acidente em 2023' } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('RAMON_LEAD_CAPTURE_TOKEN').and_return(token)
    allow(ENV).to receive(:[]).with('RAMON_LEAD_CAPTURE_ACCOUNT_ID').and_return(account.id.to_s)
  end

  describe 'POST /public/api/v1/ramon_leads/:capture_token' do
    it 'cria contact + lead na primeira etapa por position, com source e nota da mensagem' do
      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Lead, :count).by(1).and change(Contact, :count).by(1)

      expect(response).to have_http_status(:created)
      lead = Lead.last
      expect(lead.account).to eq account
      expect(lead.lead_stage).to eq stage_novo
      expect(lead.name).to eq 'Maria da Silva'
      expect(lead.source).to eq 'auxilio-acidente'
      expect(lead.contact.phone_number).to eq '+5548999887766'
      expect(lead.lead_notes.pluck(:body)).to include('Sofri acidente em 2023')
    end

    it 'honeypot preenchido devolve 200 sem criar nada' do
      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(website: 'http://spam'), as: :json
      end.not_to change(Lead, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'token errado devolve 401' do
      post '/public/api/v1/ramon_leads/token-errado', params: payload, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(Lead.count).to eq 0
    end

    it 'token não configurado no servidor devolve 401' do
      allow(ENV).to receive(:[]).with('RAMON_LEAD_CAPTURE_TOKEN').and_return(nil)
      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'telefone inválido devolve 422' do
      post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(telefone: '999'), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Lead.count).to eq 0
    end

    it 'telefone repetido reusa o Contact e, com lead ABERTO existente, cria nota em vez de duplicar' do
      contact = create(:contact, account: account, phone_number: '+5548999887766')
      lead = create(:lead, account: account, lead_stage: stage_reuniao, contact: contact)

      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json

      expect(Lead.count).to eq 1
      expect(Contact.count).to eq 1
      expect(response).to have_http_status(:created)
      expect(lead.reload.lead_notes.pluck(:body).join).to include('auxilio-acidente')
    end

    it 'lead do contato em etapa ganha/perdida NÃO bloqueia lead novo' do
      stage_ganho = create(:lead_stage, account: account, name: 'Ganho', position: 2, is_won: true)
      contact = create(:contact, account: account, phone_number: '+5548999887766')
      create(:lead, account: account, lead_stage: stage_ganho, contact: contact)

      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Lead, :count).by(1)
      expect(Lead.last.lead_stage).to eq stage_novo
    end
  end
end
