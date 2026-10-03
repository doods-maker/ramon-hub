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

  describe 'worker' do
    it 'proxima entrega a aprovada mais antiga e marca montando' do
      create(:peca, account: account, status: 'rascunho')
      a = create(:peca, account: account, status: 'aprovado')
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response.parsed_body).to include('id' => a.id, 'tipo' => 'carrossel', 'refazer_cards' => [])
      expect(a.reload).to have_attributes(status: 'montando')
      expect(a.montagem_iniciada_em).to be_present
    end

    it 'proxima também entrega refação de peça montada' do
      m = create(:peca, account: account, status: 'montado', refazer_cards: [3])
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response.parsed_body['refazer_cards']).to eq [3]
      expect(m.reload.status).to eq 'montando'
    end

    it 'proxima responde 204 sem trabalho e não entrega a mesma peça duas vezes' do
      create(:peca, account: account, status: 'aprovado')
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it 'montada grava imagens e zera refação' do
      p = create(:peca, account: account, status: 'montando', refazer_cards: [2])
      patch "/public/api/v1/conteudo/pecas/#{p.id}/montada", params: { imagens: %w[u1 u2] }.to_json, headers: headers
      expect(p.reload).to have_attributes(status: 'montado', imagens: %w[u1 u2], refazer_cards: [], erro: nil)
    end

    it 'falha de montagem nova volta pra pauta com o erro' do
      p = create(:peca, account: account, status: 'montando')
      patch "/public/api/v1/conteudo/pecas/#{p.id}/falha", params: { erro: 'Gemini 429' }.to_json, headers: headers
      expect(p.reload).to have_attributes(status: 'rascunho', erro: 'Gemini 429')
    end

    it 'falha de refação volta pra montado e não entra em loop' do
      p = create(:peca, account: account, status: 'montando', refazer_cards: [2], imagens: ['u1'])
      patch "/public/api/v1/conteudo/pecas/#{p.id}/falha", params: { erro: 'x' }.to_json, headers: headers
      expect(p.reload).to have_attributes(status: 'montado', refazer_cards: [], imagens: ['u1'])
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
