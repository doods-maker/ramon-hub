require 'rails_helper'

RSpec.describe 'Ramon IA Uso API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_ia_uso" }

  def chamada(funcao, custo, **outros)
    LlmChamada.create!({ account: account, funcao: funcao, model: 'deepseek-chat', input_tokens: 100, output_tokens: 10,
                         custo_usd: custo, created_at: Time.current }.merge(outros))
  end

  it 'agente não vê nem muda', :aggregate_failures do
    get url, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    patch url, params: { teto_diario_usd: 5 }, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'soma o período por função, modelo e dia; agente @claude e fluxos de hoje', :aggregate_failures do
    chamada('copiloto', 0.5)
    chamada('copiloto', nil, status: 'erro')
    chamada('atendimento', 1.25, model: 'deepseek-v4-pro')
    chamada('copiloto', 9, created_at: 40.days.ago)
    account.agente_execucoes.create!(pedido: 'resumo', status: 'ok', custo_usd: 0.42)
    Redis::Alfred.set("RAMON::FLUXO_IA::#{account.id}::#{Time.find_zone!('America/Sao_Paulo').today}", 3)

    get url, params: { periodo: '7d' }, headers: admin.create_new_auth_token

    body = response.parsed_body
    expect(body['total']).to include('chamadas' => 3, 'erros' => 1, 'sem_preco' => 1, 'input_tokens' => 300)
    expect(body['total']['custo_usd']).to be_within(0.001).of(1.75)
    expect(body['por_funcao'].map { |linha| linha.values_at('chave', 'chamadas') }).to eq([['atendimento', 1], ['copiloto', 2]])
    expect(body['por_dia'].size).to eq(7)
    expect(body['agente']).to include('hoje' => 1, 'teto' => 30, 'custo_hoje_usd' => 0.42)
    expect(body['fluxos']['hoje']).to eq(3)
  end

  it 'mostra provedor/modelo em vigor por função, chaves e a assinatura só no agente', :aggregate_failures do
    with_modified_env DEEPSEEK_API_KEY: 'k', OPENAI_API_KEY: nil, ANTHROPIC_API_KEY: nil do
      get url, headers: admin.create_new_auth_token, as: :json
    end

    escolhas = response.parsed_body['escolhas'].index_by { |escolha| escolha['funcao'] }
    expect(escolhas.keys).to eq(%w[atendimento copiloto documentos agente])
    expect(escolhas['agente']).to include('provider' => 'claude_vps', 'modelos' => [])
    modelos = escolhas.values_at('atendimento', 'copiloto', 'documentos').flat_map { |escolha| escolha['modelos'] }
    expect(modelos.pluck('provider').uniq).not_to include('claude_vps')
    expect(response.parsed_body['chaves']).to include('deepseek' => true, 'openai' => false)
  end

  it 'admin define e limpa o teto diário (e recusa valor inválido)', :aggregate_failures do
    patch url, params: { teto_diario_usd: '2,50' }, headers: admin.create_new_auth_token, as: :json
    expect(Ramon::IaGastoAlerta.teto(account.reload)).to eq(2.5)

    patch url, params: { teto_diario_usd: '-1' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch url, params: { teto_diario_usd: '' }, headers: admin.create_new_auth_token, as: :json
    expect(Ramon::IaGastoAlerta.teto(account.reload)).to be_nil
  end
end
