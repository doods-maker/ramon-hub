require 'rails_helper'

RSpec.describe 'Leads API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:qualif) { account.lead_stages.find_by(name: 'Qualificação') }

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
end
