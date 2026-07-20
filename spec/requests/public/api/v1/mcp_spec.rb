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

    # Com Content-Type application/json o middleware do Rails já barra corpo
    # malformado com 400 antes do controller; o handler -32700 cobre os demais
    # content-types (o transporte MCP não obriga o header).
    it 'corpo não-JSON vira erro -32700' do
      with_modified_env(RAMON_MCP_TOKEN: token) do
        post "/public/api/v1/mcp/#{token}", params: 'não é json', headers: { 'CONTENT_TYPE' => 'text/plain' }
      end
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']['code']).to eq(-32_700)
    end
  end

  describe 'tools/list' do
    it 'lista as ferramentas de leitura do AdvBox' do
      post_mcp(rpc('tools/list'))
      names = response.parsed_body['result']['tools'].pluck('name')
      expect(names).to include('advbox_buscar_processos', 'advbox_processo', 'advbox_movimentacoes',
                               'advbox_tarefas', 'advbox_buscar_clientes', 'advbox_ultimas_movimentacoes')
    end

    it 'lista as ferramentas de escrita e a de configurações (fase 2 do item 29)' do
      post_mcp(rpc('tools/list'))
      names = response.parsed_body['result']['tools'].pluck('name')
      expect(names).to include('advbox_configuracoes', 'advbox_criar_tarefa', 'advbox_criar_movimentacao',
                               'advbox_criar_cliente', 'advbox_criar_processo', 'advbox_editar_processo',
                               'advbox_criar_transacao', 'advbox_editar_transacao')
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

  describe 'tools/call de escrita (fase 2 do item 29)' do
    it 'criar tarefa mapeia os argumentos PT-BR pro payload de POST /posts' do
      stub = stub_request(:post, 'https://app.advbox.com.br/api/v1/posts')
             .with(body: hash_including('from' => '266778', 'guests' => [266_778], 'tasks_id' => '8745394',
                                        'lawsuits_id' => '123', 'comments' => 'Ligar pro cliente'))
             .to_return(status: 200, body: { posts_id: 1 }.to_json, headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_tarefa',
                                   arguments: { processo_id: 123, tipo_tarefa_id: 8_745_394, responsavel_id: 266_778,
                                                descricao: 'Ligar pro cliente' } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'criar tarefa com hora e criador manda start_time/end_time (com o end_date que a API exige) e o from separado do responsável' do
      stub = stub_request(:post, 'https://app.advbox.com.br/api/v1/posts')
             .with(body: hash_including('start_date' => '2026-07-22', 'start_time' => '14:30',
                                        'end_time' => '15:00', 'end_date' => '2026-07-22',
                                        'from' => '999', 'guests' => [266_778], 'display_schedule' => true))
             .to_return(status: 200, body: { posts_id: 1 }.to_json, headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_tarefa',
                                   arguments: { processo_id: 123, tipo_tarefa_id: 8_745_394, responsavel_id: 266_778,
                                                criador_id: 999, data: '2026-07-22', hora_inicio: '14:30', hora_fim: '15:00',
                                                exibir_agenda: true } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'criar movimentação converte a data ISO pro DD/MM/YYYY que a API exige' do
      stub = stub_request(:post, 'https://app.advbox.com.br/api/v1/lawsuits/movement')
             .with(body: hash_including('lawsuit_id' => 123, 'date' => '15/07/2026', 'description' => 'Cliente trouxe o laudo médico'))
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_movimentacao',
                                   arguments: { processo_id: 123, descricao: 'Cliente trouxe o laudo médico', data: '2026-07-15' } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'criar transação traduz receita/despesa e o valor pro formato com vírgula' do
      stub = stub_request(:post, 'https://app.advbox.com.br/api/v1/transactions')
             .with(body: hash_including('entry_type' => 'income', 'amount' => '1234,50', 'date_due' => '2026-08-01'))
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_transacao',
                                   arguments: { tipo: 'receita', valor: 1234.5, vencimento: '2026-08-01', responsavel_id: 1,
                                                conta_id: 2, categoria_id: 3, centro_custo_id: 4 } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'editar processo manda só os campos alterados via PUT' do
      stub = stub_request(:put, 'https://app.advbox.com.br/api/v1/lawsuits/55')
             .with(body: { stages_id: 99 }.to_json)
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_editar_processo', arguments: { id: 55, etapa_id: 99 } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it '4xx do AdvBox vira resultado isError com o corpo da recusa' do
      stub_request(:post, 'https://app.advbox.com.br/api/v1/lawsuits/movement')
        .to_return(status: 422, body: { error: 'description muito curta' }.to_json, headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_movimentacao', arguments: { processo_id: 1, descricao: 'curta demais não' } }))

      result = response.parsed_body['result']
      expect(result['isError']).to be true
      expect(result['content'].first['text']).to include('422', 'description muito curta')
    end

    it 'data fora do formato ISO vira resultado isError, não 500' do
      post_mcp(rpc('tools/call', { name: 'advbox_criar_movimentacao',
                                   arguments: { processo_id: 1, descricao: 'movimentação de teste', data: '15/07/2026' } }))

      result = response.parsed_body['result']
      expect(result['isError']).to be true
      expect(result['content'].first['text']).to include 'YYYY-MM-DD'
    end

    it 'criar cliente normaliza o celular e mapeia os campos pro POST /customers' do
      stub = stub_request(:post, 'https://app.advbox.com.br/api/v1/customers')
             .with(body: hash_including('name' => 'Maria de Teste', 'users_id' => 266_778, 'customers_origins_id' => 5,
                                        'cellphone' => '48999990000', 'identification' => '529.982.247-25'))
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_cliente',
                                   arguments: { nome: 'Maria de Teste', responsavel_id: 266_778, origem_id: 5,
                                                celular: '(48) 99999-0000', cpf: '529.982.247-25' } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'criar processo vincula os clientes via customers_id no POST /lawsuits' do
      stub = stub_request(:post, 'https://app.advbox.com.br/api/v1/lawsuits')
             .with(body: hash_including('customers_id' => [11, 22], 'users_id' => 1, 'stages_id' => 2, 'type_lawsuits_id' => 3))
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_processo',
                                   arguments: { cliente_ids: [11, 22], responsavel_id: 1, etapa_id: 2, tipo_id: 3 } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'editar transação manda só os campos alterados via PUT /transactions' do
      stub = stub_request(:put, 'https://app.advbox.com.br/api/v1/transactions/9')
             .with(body: { amount: '2500,00' }.to_json)
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_editar_transacao', arguments: { id: 9, valor: 2500 } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'consulta as configurações da conta (GET /settings)' do
      stub = stub_request(:get, 'https://app.advbox.com.br/api/v1/settings')
             .to_return(status: 200, body: { users: [{ id: 1, name: 'Eduardo' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_configuracoes', arguments: {} }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['content'].first['text']).to include 'Eduardo'
    end
  end

  # O server não valida inputSchema — input fora do contrato tem que degradar
  # em isError ou erro JSON-RPC, nunca 500 cru (revisão adversarial do PR #80).
  describe 'robustez contra input fora do schema' do
    it 'argumento de tipo errado (valor booleano) vira isError, não 500' do
      post_mcp(rpc('tools/call', { name: 'advbox_criar_transacao',
                                   arguments: { tipo: 'receita', valor: true, vencimento: '2026-08-01', responsavel_id: 1,
                                                conta_id: 2, categoria_id: 3, centro_custo_id: 4 } }))

      result = response.parsed_body['result']
      expect(result['isError']).to be true
      expect(result['content'].first['text']).to include 'Argumento inválido'
    end

    it 'tipo de transação fora do enum vira isError em vez de sumir do payload em silêncio' do
      post_mcp(rpc('tools/call', { name: 'advbox_criar_transacao',
                                   arguments: { tipo: 'Receita', valor: 10, vencimento: '2026-08-01', responsavel_id: 1,
                                                conta_id: 2, categoria_id: 3, centro_custo_id: 4 } }))

      result = response.parsed_body['result']
      expect(result['isError']).to be true
      expect(result['content'].first['text']).to include 'Argumento inválido'
    end

    it 'data null na movimentação usa a data de hoje em vez de estourar' do
      stub = stub_request(:post, 'https://app.advbox.com.br/api/v1/lawsuits/movement')
             .with(body: hash_including('date' => Time.zone.today.strftime('%d/%m/%Y')))
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post_mcp(rpc('tools/call', { name: 'advbox_criar_movimentacao',
                                   arguments: { processo_id: 1, descricao: 'movimentação de teste', data: nil } }))

      expect(stub).to have_been_requested
      expect(response.parsed_body['result']['isError']).to be false
    end

    it 'params que não é objeto vira isError de ferramenta desconhecida' do
      post_mcp(rpc('tools/call', 'não sou um hash'))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['result']['isError']).to be true
    end

    it 'arguments que não é objeto vira isError de argumento' do
      post_mcp(rpc('tools/call', { name: 'advbox_cliente', arguments: [1] }))
      result = response.parsed_body['result']
      expect(result['isError']).to be true
      expect(result['content'].first['text']).to include 'Argumento inválido'
    end

    it 'initialize com params fora do formato responde com a versão padrão' do
      post_mcp(rpc('initialize', 'x'))
      expect(response.parsed_body['result']['protocolVersion']).to eq '2025-06-18'
    end

    it 'exceção inesperada vira erro JSON-RPC -32603, não 500 cru do Rails' do
      allow(Ramon::AdvboxMcpService).to receive(:handle).and_raise(RuntimeError, 'boom')
      post_mcp(rpc('tools/list'))
      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body['error']['code']).to eq(-32_603)
    end

    it 'batch acima de 20 entradas vira -32600' do
      post_mcp(Array.new(21) { |i| rpc('ping', {}, id: i + 1) })
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']['code']).to eq(-32_600)
    end
  end
end
