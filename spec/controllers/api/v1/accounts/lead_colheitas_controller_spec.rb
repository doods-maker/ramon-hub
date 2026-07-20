require 'rails_helper'

RSpec.describe 'Lead Colheitas API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }

  def extrair(headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/colheita", headers: headers, as: :json
  end

  it 'exige autenticação' do
    extrair({})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'enfileira a extração sob demanda pelo lead_id e responde 202' do
    expect { extrair }.to have_enqueued_job(Ramon::ColheitaExtractionJob).with(lead_id: lead.id)
    expect(response).to have_http_status(:accepted)
  end
end
