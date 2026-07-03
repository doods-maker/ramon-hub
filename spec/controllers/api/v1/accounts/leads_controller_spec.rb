require 'rails_helper'

RSpec.describe 'Leads API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:qualif) { account.lead_stages.find_by(name: 'Qualificação') }
  let(:perdido) { account.lead_stages.find_by(is_lost: true) }

  it 'cria um lead na etapa Novo' do
    post "/api/v1/accounts/#{account.id}/leads",
         params: { name: 'João', lead_stage_id: novo.id },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['name']).to eq('João')
    expect(account.leads.count).to eq(1)
  end

  it 'move um lead de etapa via update' do
    lead = create(:lead, account: account, lead_stage: novo, name: 'Ana')
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
          params: { lead_stage_id: qualif.id, position: 1.5 },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(lead.reload.lead_stage).to eq(qualif)
    expect(lead.position).to eq(1.5)
  end

  it 'lista os leads da conta' do
    create(:lead, account: account, lead_stage: novo)
    get "/api/v1/accounts/#{account.id}/leads",
        headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
  end

  it 'serializa value/source + nomes desnormalizados + contato', :aggregate_failures do
    contact = create(:contact, account: account, name: 'Cliente X',
                               phone_number: '+5547999990000', email: 'x@cli.com')
    bt = account.benefit_types.find_by(name: 'Auxílio-acidente')
    lead = create(:lead, account: account, lead_stage: novo, contact: contact,
                         benefit_type: bt, value: 12_000.50, source: 'Meta Ads')
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
        headers: admin.create_new_auth_token, as: :json
    body = response.parsed_body
    expect(body['value'].to_f).to eq(12_000.50)
    expect(body['source']).to eq('Meta Ads')
    expect(body['stage_name']).to eq('Novo')
    expect(body['stage_color']).to eq('#6b7280')
    expect(body['benefit_type_name']).to eq('Auxílio-acidente')
    expect(body['contact_name']).to eq('Cliente X')
    expect(body['contact_phone']).to eq('+5547999990000')
    expect(body['contact_email']).to eq('x@cli.com')
  end

  it 'update aceita value/source' do
    lead = create(:lead, account: account, lead_stage: novo)
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
          params: { value: 8500.25, source: 'Meta Ads' },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    lead.reload
    expect(lead.value).to eq(8500.25)
    expect(lead.source).to eq('Meta Ads')
  end

  describe 'POST /api/v1/accounts/{account}/leads/for_conversation' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }

    it 'creates a lead in the default stage when none exists' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(account.leads, :count).by(1)
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['conversation_id']).to eq(conversation.id)
      expect(body['stage_name']).to be_present
    end

    it 'returns the existing lead without creating a duplicate' do
      existing = account.leads.create!(conversation: conversation, contact: contact,
                                       lead_stage: account.lead_stages.order(:position).first,
                                       name: 'X')
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))
      expect(response.parsed_body['id']).to eq(existing.id)
    end

    it 'dedupes by contact when the same contact has a lead on a different conversation' do
      existing = account.leads.create!(conversation: conversation, contact: contact,
                                       lead_stage: account.lead_stages.order(:position).first,
                                       name: 'X')
      new_conversation = create(:conversation, account: account, contact: contact)

      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: new_conversation.id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))

      expect(response.parsed_body['id']).to eq(existing.id)
      expect(existing.reload.conversation_id).to eq(new_conversation.id)
    end
  end

  describe 'GET /api/v1/accounts/{account}/leads (filtros)' do
    let(:bpc_teste) { account.benefit_types.create!(name: 'BPC-teste') }

    def ids(response)
      response.parsed_body['payload'].map { |l| l['id'] }
    end

    it 'sem params retorna todos os leads' do
      a = account.leads.create!(name: 'A', lead_stage: novo)
      b = account.leads.create!(name: 'B', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      expect(ids(response)).to contain_exactly(a.id, b.id)
    end

    it 'filtra por source' do
      a = account.leads.create!(name: 'A', lead_stage: novo, source: 'meta-ads')
      account.leads.create!(name: 'B', lead_stage: novo, source: 'indicacao')
      get "/api/v1/accounts/#{account.id}/leads",
          params: { source: 'meta-ads' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por benefit_type_id' do
      a = account.leads.create!(name: 'A', lead_stage: novo, benefit_type: bpc_teste)
      account.leads.create!(name: 'B', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { benefit_type_id: bpc_teste.id },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por agent_id casando sdr OU closer' do
      agent = create(:user, account: account, role: :agent)
      as_sdr = account.leads.create!(name: 'S', lead_stage: novo, sdr_id: agent.id)
      as_closer = account.leads.create!(name: 'C', lead_stage: novo, closer_id: agent.id)
      account.leads.create!(name: 'N', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { agent_id: agent.id },
          headers: admin.create_new_auth_token
      expect(ids(response)).to contain_exactly(as_sdr.id, as_closer.id)
    end

    it 'busca q por nome do lead mesmo sem contato' do
      hit = account.leads.create!(name: 'Joana Silva', lead_stage: novo)
      account.leads.create!(name: 'Outro', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { q: 'joana' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([hit.id])
    end

    it 'filtra por lead_stage_id' do
      a = account.leads.create!(name: 'A', lead_stage: qualif)
      account.leads.create!(name: 'B', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { lead_stage_id: qualif.id },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por created_after' do
      recente = account.leads.create!(name: 'Recente', lead_stage: novo)
      antigo = account.leads.create!(name: 'Antigo', lead_stage: novo)
      antigo.update_column(:created_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
      get "/api/v1/accounts/#{account.id}/leads",
          params: { created_after: 2.days.ago.to_date.to_s },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([recente.id])
    end

    it 'filtra por stalled numa etapa com stalled_after_days' do
      parado = account.leads.create!(name: 'Parado', lead_stage: qualif)
      parado.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
      account.leads.create!(name: 'Fresco', lead_stage: qualif)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { stalled: 'true' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([parado.id])
    end

    it 'filtra por no_open_task' do
      sem_tarefa = account.leads.create!(name: 'Livre', lead_stage: novo)
      com_tarefa = account.leads.create!(name: 'Ocupado', lead_stage: novo)
      create(:lead_task, account: account, lead: com_tarefa)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { no_open_task: 'true' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([sem_tarefa.id])
    end
  end

  describe 'trava de motivo de perda no update' do
    it 'bloqueia mover para etapa perdida sem motivo com 422', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: novo, name: 'Sem motivo')
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { lead_stage_id: perdido.id },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('LOST_REASON_REQUIRED')
      expect(lead.reload.lead_stage).to eq(novo)
    end

    it 'permite mover para etapa perdida com motivo e grava lost_at', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: novo, name: 'Com motivo')
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { lead_stage_id: perdido.id, lost_reason: 'Honorário' },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      lead.reload
      expect(lead.lead_stage).to eq(perdido)
      expect(lead.lost_at).to be_present
    end

    it 'persiste custom_attributes no update' do
      lead = create(:lead, account: account, lead_stage: novo)
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { custom_attributes: { cpf: '123', origem: 'campanha' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(lead.reload.custom_attributes).to eq('cpf' => '123', 'origem' => 'campanha')
    end
  end
end
