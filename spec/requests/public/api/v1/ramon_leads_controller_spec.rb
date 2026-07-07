require 'rails_helper'

RSpec.describe 'Public Ramon Leads API', type: :request do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService):
  # 'Novo' (position 0) ... 'Fechado' (is_won) / 'Perdido' (is_lost).
  let(:account) { create(:account) }
  let(:stage_novo) { account.lead_stages.order(:position).first }
  let(:stage_reuniao) { account.lead_stages.find_by!(name: 'Reunião agendada') }
  let(:token) { 'tok-secreto' }
  let(:payload) { { nome: 'Maria da Silva', telefone: '5548999887766', campanha: 'auxilio-acidente', mensagem: 'Sofri acidente em 2023' } }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RAMON_LEAD_CAPTURE_TOKEN', nil).and_return(token)
    allow(ENV).to receive(:fetch).with('RAMON_LEAD_CAPTURE_ACCOUNT_ID', nil).and_return(account.id.to_s)
  end

  describe 'POST /public/api/v1/ramon_leads/:capture_token' do
    it 'cria contact + lead na primeira etapa por position, com source' do
      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Lead, :count).by(1).and change(Contact, :count).by(1)

      expect(response).to have_http_status(:created)
      lead = Lead.last
      expect(lead.account).to eq account
      expect(lead.lead_stage).to eq stage_novo
      expect(lead.name).to eq 'Maria da Silva'
      expect(lead.source).to eq 'auxilio-acidente'
    end

    it 'grava o telefone em E.164 e a mensagem como nota do lead' do
      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json

      lead = Lead.last
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
      allow(ENV).to receive(:fetch).with('RAMON_LEAD_CAPTURE_TOKEN', nil).and_return(nil)
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

    it 'notifica os usuários da conta quando cria lead novo' do
      create(:user, account: account, role: :administrator)

      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Notification.where(notification_type: 'ramon_lead_created'), :count).by(1)
    end

    it 'notifica também na recaptura de lead aberto existente' do
      create(:user, account: account, role: :administrator)
      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json

      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Notification.where(notification_type: 'ramon_lead_created'), :count).by(1)
    end

    it 'aceita o token via header X-Capture-Token na rota sem token no path' do
      expect do
        post '/public/api/v1/ramon_leads', params: payload, headers: { 'X-Capture-Token' => token }, as: :json
      end.to change(Lead, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it 'header com token errado devolve 401' do
      post '/public/api/v1/ramon_leads', params: payload, headers: { 'X-Capture-Token' => 'errado' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(Lead.count).to eq 0
    end

    it 'grava os parâmetros utm_* em custom_attributes.utm do lead' do
      post '/public/api/v1/ramon_leads',
           params: payload.merge(utm_source: 'facebook', utm_medium: 'cpc', utm_campaign: 'aa-julho', utm_content: 'video-1'),
           headers: { 'X-Capture-Token' => token }, as: :json

      expect(Lead.last.custom_attributes['utm']).to eq(
        'utm_source' => 'facebook', 'utm_medium' => 'cpc', 'utm_campaign' => 'aa-julho', 'utm_content' => 'video-1'
      )
    end

    it 'sem utm_* não grava chave utm' do
      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      expect(Lead.last.custom_attributes).not_to have_key('utm')
    end

    it 'lead do contato em etapa ganha/perdida NÃO bloqueia lead novo' do
      stage_ganho = account.lead_stages.find_by!(is_won: true)
      contact = create(:contact, account: account, phone_number: '+5548999887766')
      create(:lead, account: account, lead_stage: stage_ganho, contact: contact)

      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Lead, :count).by(1)
      # Lead tem default_scope por (lead_stage_id, position, id) — `.last` não é o mais recente
      expect(Lead.unscoped.order(:id).last.lead_stage).to eq stage_novo
    end

    it 'cria lead novo quando os leads do contato estão todos fechados' do
      contact = account.contacts.create!(name: 'Maria', phone_number: '+5548999990000')
      won_stage = account.lead_stages.find_by(is_won: true)
      account.leads.create!(name: 'Caso antigo', contact_id: contact.id, lead_stage: won_stage)

      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(telefone: '48 99999-0000', nome: 'Maria'), as: :json
      end.to change { account.leads.count }.by(1)
    end
  end
end
