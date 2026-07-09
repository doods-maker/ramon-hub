require 'rails_helper'

RSpec.describe 'Ramon Lead Imports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:csv_file) do
    Rack::Test::UploadedFile.new(
      StringIO.new("nome,telefone\nMaria,4899990000\n"), 'text/csv', original_filename: 'leads.csv'
    )
  end

  it 'cria o import de leads (admin) e enfileira processamento' do
    expect do
      post "/api/v1/accounts/#{account.id}/ramon_lead_imports",
           params: { import_file: csv_file },
           headers: admin.create_new_auth_token
    end.to change { account.data_imports.where(data_type: 'leads').count }.by(1)
    expect(response).to have_http_status(:success)
  end

  it 'barra agente (admin-only)' do
    post "/api/v1/accounts/#{account.id}/ramon_lead_imports",
         params: { import_file: csv_file },
         headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it '422 sem arquivo' do
    post "/api/v1/accounts/#{account.id}/ramon_lead_imports", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'mostra status e contadores' do
    import = account.data_imports.new(data_type: 'leads', status: :completed, total_records: 10, processed_records: 9)
    import.import_file.attach(io: StringIO.new("nome\n"), filename: 'l.csv', content_type: 'text/csv')
    import.save!
    get "/api/v1/accounts/#{account.id}/ramon_lead_imports/#{import.id}", headers: admin.create_new_auth_token
    body = response.parsed_body
    expect(body['status']).to eq('completed')
    expect(body['processed_records']).to eq(9)
  end
end
