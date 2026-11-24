require 'rails_helper'

RSpec.describe 'Ramon BI API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Teste') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_bi" }
  let(:html) { '<html><body>teste</body></html>' }

  # Arquivo mínimo criado na hora: o BI real nunca entra no repositório (público).
  def upload(conteudo, nome: 'bi.html', tipo: 'text/html')
    file = Tempfile.new(['bi', File.extname(nome)])
    file.write(conteudo)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, tipo, original_filename: nome)
  end

  def enviar(arquivo, user = admin)
    put url, params: { arquivo: arquivo }, headers: user.create_new_auth_token
  end

  it 'exige autenticacao' do
    get url, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'barra agente no GET e no PUT' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    enviar(upload(html), agent)
    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.ramon_bi).not_to be_attached
  end

  it 'admin sem anexo recebe enviado false' do
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to eq('enviado' => false)
  end

  it 'admin envia o html e o GET devolve conteudo, data e quem enviou' do
    enviar(upload(html))
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['enviado']).to be(true)

    get url, headers: admin.create_new_auth_token, as: :json
    body = response.parsed_body
    expect(body['html']).to eq(html)
    expect(body['enviado_por']).to eq('Admin Teste')
    expect(Time.zone.parse(body['enviado_em'])).to be_within(1.minute).of(Time.current)
  end

  it 'recusa arquivo que nao e html e mantem o anterior' do
    enviar(upload(html))
    enviar(upload('texto', nome: 'bi.txt', tipo: 'text/plain'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to be_present

    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['html']).to eq(html)
  end

  it 'recusa html acima de 5 MB' do
    enviar(upload('a' * (5.megabytes + 1)))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.ramon_bi).not_to be_attached
  end

  it 'novo envio substitui o anterior (um blob so)' do
    enviar(upload(html))
    enviar(upload('<html><body>novo</body></html>'))
    expect(response).to have_http_status(:success)
    expect(ActiveStorage::Attachment.where(record: account, name: 'ramon_bi').count).to eq(1)

    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['html']).to eq('<html><body>novo</body></html>')
  end
end
