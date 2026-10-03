require 'rails_helper'

RSpec.describe 'Public Conteudo API', type: :request do
  let(:account) { create(:account) }
  let(:token) { 'conteudo-teste' }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Conteudo-Token' => token } }
  let(:corpo) do
    { slug: '01-auxilio-acidente', rodada: '2026-10-01', tipo: 'carrossel', gancho: 'Quem tem direito',
      estilo: 'fluxo', tese: 'auxilio-acidente', notion_page_id: 'np1',
      conteudo: { fields: { capa_titulo: 'T' }, legenda: 'L', hashtags: ['#inss'] } }
  end

  around { |ex| with_modified_env(RAMON_CONTEUDO_TOKEN: token, RAMON_CONTEUDO_ACCOUNT_ID: account.id.to_s) { ex.run } }

  it 'rejeita token errado' do
    post '/public/api/v1/conteudo/pecas', params: corpo.to_json, headers: headers.merge('X-Conteudo-Token' => 'x')
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cria a pauta em rascunho' do
    post '/public/api/v1/conteudo/pecas', params: corpo.to_json, headers: headers
    expect(response).to have_http_status(:created)
    peca = account.pecas.last
    expect(peca).to have_attributes(slug: '01-auxilio-acidente', status: 'rascunho', tipo: 'carrossel',
                                    notion_page_id: 'np1', legenda: "L\n\n#inss")
    expect(peca.conteudo['fields']['capa_titulo']).to eq 'T'
  end

  it 'é idempotente pelo slug (rotina pode re-rodar)' do
    2.times { post '/public/api/v1/conteudo/pecas', params: corpo.to_json, headers: headers }
    expect(response).to have_http_status(:ok)
    expect(account.pecas.count).to eq 1
  end

  it '422 com tipo fora da v1' do
    post '/public/api/v1/conteudo/pecas', params: corpo.merge(tipo: 'video').to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
