require 'rails_helper'

RSpec.describe 'Roteiro passos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thesis) { create(:thesis, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/roteiro_passos" }

  def criar(params, user = admin)
    post url, params: params, headers: user.create_new_auth_token, as: :json
  end

  it 'lista os passos da conta e o catálogo das calculadoras (agente lê)' do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('chave')).to eq(['nome'])
    expect(response.parsed_body.dig('calculadoras', 'periodo_de_graca', 'campos')).to include('ultimo_vinculo')
  end

  it 'cria passo comum e passo da tese no fim do escopo, marcados como editados' do
    criar({ titulo: 'Nome', chave: 'nome', tipo_resposta: 'texto' })
    expect(response.parsed_body).to include('thesis_id' => nil, 'position' => 0, 'edited' => true)
    criar({ titulo: 'Recebeu', chave: 'recebeu', tipo_resposta: 'sim_nao', thesis_id: thesis.id })
    expect(response.parsed_body).to include('thesis_id' => thesis.id, 'position' => 0)
  end

  it 'barra agente no cadastro' do
    criar({ titulo: 'Nome', chave: 'nome' }, agent)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'recusa destino e campo de calculadora sem passo, e chave repetida entre comuns e tese' do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    criar({ titulo: 'X', chave: 'x', thesis_id: thesis.id, tipo_resposta: 'sim_nao',
            saidas: [{ id: 's1', quando: 'sim', acao: 'ir_para', alvo: 'sumiu' }] })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include("'sumiu' não existe")

    criar({ titulo: 'Graça', chave: 'graca', thesis_id: thesis.id, tipo_resposta: 'data', calculadora: 'periodo_de_graca',
            calculadora_campos: { ultimo_vinculo: 'graca', evento: 'acidente', idade: 'graca' } })
    expect(response.parsed_body['error']).to include("passo 'acidente'").and include("campo 'idade'")

    criar({ titulo: 'Nome', chave: 'nome', thesis_id: thesis.id })
    expect(response.parsed_body['error']).to include('já existe nos passos comuns')
    expect(RoteiroPasso.count).to eq(1)
  end

  it 'passo da tese aponta para comum e para si; passo comum não aponta para passo de tese' do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda')
    criar({ titulo: 'X', chave: 'x', thesis_id: thesis.id, tipo_resposta: 'sim_nao',
            saidas: [{ id: 's1', quando: 'sim', acao: 'ir_para', alvo: 'nome' }, { id: 's2', quando: '*', acao: 'ir_para', alvo: 'x' }] })
    expect(response).to have_http_status(:success)

    criar({ titulo: 'Comum', chave: 'comum', tipo_resposta: 'sim_nao',
            saidas: [{ id: 's1', quando: '*', acao: 'ir_para', alvo: 'renda' }] })
    expect(response.parsed_body['error']).to include("'renda' não existe")
  end

  it 'erro do model volta 422 com a mensagem (motivo obrigatório)' do
    criar({ titulo: 'X', chave: 'x', tipo_resposta: 'sim_nao', saidas: [{ id: 's1', quando: 'sim', acao: 'humano' }] })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to include('motivo obrigatório')
  end

  it 'editar não troca a chave e marca editado' do
    passo = create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', titulo: 'Renda')
    patch "#{url}/#{passo.id}", params: { titulo: 'Renda da casa', chave: 'outra' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(passo.reload).to have_attributes(titulo: 'Renda da casa', chave: 'renda', edited: true)
  end

  it 'não remove passo apontado por outro; remove o livre' do
    alvo = create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', titulo: 'Renda')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', titulo: 'Recebeu',
                           saidas: [{ 'id' => 's1', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'renda' }])
    delete "#{url}/#{alvo.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Recebeu')

    livre = create(:roteiro_passo, account: account, thesis: thesis, chave: 'livre')
    delete "#{url}/#{livre.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(RoteiroPasso.exists?(livre.id)).to be(false)
  end

  it 'reordena pela lista de ids' do
    a = create(:roteiro_passo, account: account, thesis: thesis, position: 0)
    b = create(:roteiro_passo, account: account, thesis: thesis, position: 1)
    post "#{url}/reorder", params: { ids: [b.id, a.id] }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect([b.reload.position, a.reload.position]).to eq([0, 1])
    expect([b.edited, a.edited]).to eq([true, true])
  end
end
