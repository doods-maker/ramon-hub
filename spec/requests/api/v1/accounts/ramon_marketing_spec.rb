require 'rails_helper'

RSpec.describe 'Ramon Marketing API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_marketing" }
  let(:auth) { admin.create_new_auth_token }

  it 'barra agente (só admin)' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'mostra o estado da Meta desligado e os custos lançados' do
    create(:account) # outra conta não aparece
    MarketingCusto.create!(account: account, data: Date.new(2026, 11, 1), valor: 1908, categoria: 'equipe')
    with_modified_env('RAMON_META_GASTO' => nil, 'RAMON_META_AD_ACCOUNT_ID' => nil) { get url, headers: auth, as: :json }

    corpo = response.parsed_body
    expect(corpo['status']).to include('gasto' => false, 'conta_anuncios' => false, 'ultimo_gasto' => nil)
    expect(corpo['custos'].pluck('categoria')).to eq(['equipe'])
    expect(corpo['categorias']).to include('impulsionamento', 'equipe')
  end

  it 'lança e remove um custo' do
    post "#{url}/custos", params: { data: '2026-11-05', valor: '350.00', categoria: 'criativo', observacao: 'freela' }, headers: auth, as: :json
    expect(response).to have_http_status(:created)
    custo = MarketingCusto.find(response.parsed_body['id'])
    expect(custo).to have_attributes(account_id: account.id, user_id: admin.id, valor: 350)

    delete "#{url}/custos/#{custo.id}", headers: auth, as: :json
    expect(response).to have_http_status(:no_content)
    expect(MarketingCusto.count).to eq(0)
  end

  it 'tese de outra conta não entra' do
    de_fora = create(:thesis, account: create(:account), name: 'Tese de fora')
    post "#{url}/custos", params: { data: '2026-11-05', valor: '10', categoria: 'outro', thesis_id: de_fora.id }, headers: auth, as: :json
    expect(response).to have_http_status(:not_found)
    expect(MarketingCusto.count).to eq(0)
  end

  it 'custo inválido volta 422 com a mensagem' do
    post "#{url}/custos", params: { data: '2026-11-05', valor: '0', categoria: 'xyz' }, headers: auth, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to be_present
  end

  it 'importa o CSV do Gerenciador e explica quando falta coluna' do
    post "#{url}/importar_gasto", params: { texto: "Ad ID,Day,Amount spent (BRL)\n111,2026-10-14,10.50\n" }, headers: auth, as: :json
    expect(response.parsed_body['linhas']).to eq(1)

    post "#{url}/importar_gasto", params: { texto: "Ad name,Amount spent (BRL)\nA,1\n" }, headers: auth, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/Faltam colunas/)
  end

  it 'importa o mensal.json do modelo' do
    post "#{url}/importar_metas", params: { texto: [{ mes: 'Nov/26', contratos: 15 }].to_json }, headers: auth, as: :json
    expect(response.parsed_body['meses']).to eq(1)
    expect(MarketingMeta.where(account: account).count).to eq(1)
  end

  describe 'controle das metas' do
    before { Ramon::MetasDoModelo.importar(account, [{ mes: 'Nov/26', contratos: 15, cac: 900 }].to_json) }

    let(:meta) { MarketingMeta.find_by!(account: account, metrica: 'contratos') }

    def bi_metas
      ActiveRecord::Base.connection.exec_query("SELECT * FROM bi_marketing_metas WHERE account_id = #{account.id}").to_a
    end

    it 'nascem desligadas (fora do Metabase) e o interruptor liga e desliga' do
      expect(bi_metas).to be_empty
      put "#{url}/metas_ativas", params: { ativas: true }, headers: auth, as: :json
      expect(bi_metas.size).to eq(2)

      get url, headers: auth, as: :json
      expect(response.parsed_body['metas']).to include('ativas' => true)
      expect(response.parsed_body.dig('metas', 'linhas').size).to eq(2)

      put "#{url}/metas_ativas", params: { ativas: false }, headers: auth, as: :json
      expect(bi_metas).to be_empty
    end

    it 'edita uma meta, marca como editada e o arquivo novo pede confirmação (409)' do
      patch "#{url}/metas/#{meta.id}", params: { valor: '18' }, headers: auth, as: :json
      expect(response.parsed_body).to include('editada' => true)
      expect(meta.reload.valor).to eq(18)

      texto = [{ mes: 'Nov/26', contratos: 20 }].to_json
      post "#{url}/importar_metas", params: { texto: texto }, headers: auth, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include('precisa_confirmar' => true, 'editadas' => 1)

      post "#{url}/importar_metas", params: { texto: texto, confirmar: true }, headers: auth, as: :json
      expect(response.parsed_body['meses']).to eq(1)
    end

    it 'recusa valor inválido e apaga todas' do
      patch "#{url}/metas/#{meta.id}", params: { valor: 'abc' }, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      delete "#{url}/metas", headers: auth, as: :json
      expect(response).to have_http_status(:no_content)
      expect(MarketingMeta.where(account: account)).to be_empty
    end
  end
end
