require 'rails_helper'

RSpec.describe 'Public MCP (AdvBox) API', type: :request do
  let(:token) { 'token-mcp-teste' }

  def post_mcp(body, path_token: token, mcp_token: 'token-mcp-teste', advbox_token: 'token-advbox')
    with_modified_env(RAMON_MCP_TOKEN: mcp_token, ADVBOX_API_TOKEN: advbox_token) do
      post "/public/api/v1/mcp/#{path_token}", params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
    end
  end

  def rpc(method, params = {}, id: 1)
    { jsonrpc: '2.0', id: id, method: method, params: params }
  end

  describe 'autenticação' do
    it 'rejeita token errado com 401' do
      post_mcp(rpc('tools/list'), path_token: 'errado')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita quando o token não está configurado no servidor' do
      post_mcp(rpc('tools/list'), mcp_token: nil)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'GET responde 405 (sem stream SSE)' do
      with_modified_env(RAMON_MCP_TOKEN: token) do
        get "/public/api/v1/mcp/#{token}"
      end
      expect(response).to have_http_status(:method_not_allowed)
    end
  end

  describe 'protocolo' do
    it 'responde ao initialize com versão negociada e ferramentas anunciadas' do
      post_mcp(rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {} }))
      expect(response).to have_http_status(:ok)
      result = response.parsed_body['result']
      expect(result['protocolVersion']).to eq '2025-06-18'
      expect(result['capabilities']).to have_key 'tools'
      expect(result['serverInfo']['name']).to eq 'ramon-hub-advbox'
    end

    it 'notificação (sem id) responde 202 sem corpo JSON-RPC' do
      post_mcp({ jsonrpc: '2.0', method: 'notifications/initialized' })
      expect(response).to have_http_status(:accepted)
    end

    it 'método desconhecido vira erro JSON-RPC -32601' do
      post_mcp(rpc('resources/list'))
      expect(response.parsed_body['error']['code']).to eq(-32_601)
    end

    it 'corpo não-JSON vira erro -32700' do
      with_modified_env(RAMON_MCP_TOKEN: token) do
        post "/public/api/v1/mcp/#{token}", params: 'não é json', headers: { 'CONTENT_TYPE' => 'application/json' }
      end
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']['code']).to eq(-32_700)
    end
  end

  describe 'tools/list' do
    it 'lista as ferramentas somente-leitura do AdvBox' do
      post_mcp(rpc('tools/list'))
      names = response.parsed_body['result']['tools'].pluck('name')
      expect(names).to include('advbox_buscar_processos', 'advbox_processo', 'advbox_movimentacoes',
                               'advbox_tarefas', 'advbox_buscar_clientes', 'advbox_ultimas_movimentacoes')
    end
  end

  describe 'tools/call' do
    it 'consulta processo no AdvBox e devolve o JSON como texto' do
      stub = stub_request(:get, 'https://app.advbox.com.br/api/v1/lawsuits/123')
             .with(headers: { 'Authorization' => 'Bearer token-advbox' })
             .to_return(status: 200, body: { data: { id: 123, process_number: '0000000-00.2026.4.04.7207' } }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_processo', arguments: { id: 123 } }))

      expect(stub).to have_been_requested
      result = response.parsed_body['result']
      expect(result['isError']).to be false
      expect(result['content'].first['text']).to include '0000000-00.2026.4.04.7207'
    end

    it 'mapeia filtros PT-BR de tarefas para os query params da API' do
      stub = stub_request(:get, 'https://app.advbox.com.br/api/v1/posts')
             .with(query: { 'deadline_start' => '2026-07-13', 'deadline_end' => '2026-07-19', 'limit' => '50' })
             .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_tarefas', arguments: { prazo_de: '2026-07-13', prazo_ate: '2026-07-19' } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'ferramenta desconhecida vira resultado isError, não erro de protocolo' do
      post_mcp(rpc('tools/call', { name: 'advbox_apagar_tudo', arguments: {} }))
      result = response.parsed_body['result']
      expect(result['isError']).to be true
      expect(result['content'].first['text']).to include 'ferramenta desconhecida'
    end

    it 'AdvBox sem token configurado vira resultado isError com a mensagem do cliente' do
      post_mcp(rpc('tools/call', { name: 'advbox_processo', arguments: { id: 1 } }), advbox_token: nil)
      result = response.parsed_body['result']
      expect(result['isError']).to be true
      expect(result['content'].first['text']).to include 'ADVBOX_API_TOKEN'
    end
  end
end
