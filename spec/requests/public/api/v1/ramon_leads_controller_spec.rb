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

    it 'telefone repetido reusa o Contact e, com lead ABERTO existente, registra atividade em vez de duplicar' do
      contact = create(:contact, account: account, phone_number: '+5548999887766')
      lead = create(:lead, account: account, lead_stage: stage_reuniao, contact: contact)

      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json

      expect(Lead.count).to eq 1
      expect(Contact.count).to eq 1
      expect(response).to have_http_status(:created)
      activity = lead.lead_activities.find_by(kind: 'lp_recaptured')
      expect(activity&.to_value).to eq 'auxilio-acidente'
      expect(lead.lead_notes.pluck(:body)).to include('Sofri acidente em 2023')
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

    it 'com consent no payload grava consent_marketing no contact (aceite + timestamp + origem lp:)' do
      post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(consent: 'true'), as: :json

      consent = Contact.last.custom_attributes['consent_marketing']
      expect(consent['granted']).to be true
      expect(consent['source']).to eq 'lp:auxilio-acidente'
      expect(Time.zone.parse(consent['at'])).to be_within(1.minute).of(Time.current)
    end

    it 'sem campanha usa utm_campaign na origem do consentimento' do
      post "/public/api/v1/ramon_leads/#{token}",
           params: payload.merge(consent: '1', campanha: '', utm_campaign: 'aa-julho'), as: :json

      expect(Contact.last.custom_attributes.dig('consent_marketing', 'source')).to eq 'lp:aa-julho'
    end

    it 'sem consent (ou consent falso) não grava consent_marketing' do
      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      expect(Contact.last.custom_attributes).not_to have_key('consent_marketing')

      post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(consent: 'false'), as: :json
      expect(Contact.last.custom_attributes).not_to have_key('consent_marketing')
    end

    it 'recaptura de lead aberto com consent grava no contact existente' do
      contact = create(:contact, account: account, phone_number: '+5548999887766')
      create(:lead, account: account, lead_stage: stage_reuniao, contact: contact)

      post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(consent: 'on'), as: :json

      expect(contact.reload.custom_attributes.dig('consent_marketing', 'granted')).to be true
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
        post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(telefone: '55 48 99999-0000', nome: 'Maria'), as: :json
      end.to change { account.leads.count }.by(1)
    end

    context 'with structured quiz payload' do
      let(:quiz_params) do
        {
          qualificado: true,
          duvidas: ['Renda familiar'],
          respostas: [
            { id: 'sequela', pergunta: 'Sequela permanente', resposta: 'Sim, tenho sequela', valor: 'sim' },
            { id: 'renda', pergunta: 'Renda por pessoa', resposta: 'Perto de meio salário', valor: 'meio-salario', duvida: true }
          ]
        }
      end

      it 'stores the quiz under custom_attributes and starts at qualificacao' do
        post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(quiz_params), as: :json

        lead = Lead.last
        expect(lead.custom_attributes['quiz']).to include(
          'qualificado' => true,
          'duvidas' => ['Renda familiar']
        )
        expect(lead.custom_attributes['quiz']['respostas'].length).to eq(2)
        expect(lead.lead_stage.label).to eq('fase-qualificacao')
      end

      it 'starts a disqualified quiz lead at the first stage' do
        post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(quiz_params, qualificado: false), as: :json
        expect(Lead.last.lead_stage).to eq stage_novo
      end

      it 'merges the quiz into an existing open lead without moving its stage' do
        contact = create(:contact, account: account, phone_number: '+5548999887766')
        existing = create(:lead, account: account, contact: contact, lead_stage: stage_reuniao)

        post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(quiz_params), as: :json

        expect(existing.reload.custom_attributes.dig('quiz', 'qualificado')).to be(true)
        expect(existing.lead_stage).to eq stage_reuniao
      end
    end

    context 'without quiz payload' do
      it 'keeps the lead at the first stage' do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
        expect(Lead.last.lead_stage).to eq stage_novo
      end
    end
  end
end
