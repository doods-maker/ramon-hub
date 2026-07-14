# Servidor MCP (Model Context Protocol) mínimo sobre a API do AdvBox, para os
# custom connectors dos projetos Claude Cowork da banca (item 29 do plano
# mestre). Transporte streamable HTTP sem SSE: cada POST JSON-RPC recebe uma
# resposta JSON única; GET (stream) responde 405 no controller. v1 é SOMENTE
# LEITURA — escrita (criar tarefa, movimentação) fica para fatia futura com
# escopo/auditoria próprios.
class Ramon::AdvboxMcpService
  PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
  SERVER_INFO = { name: 'ramon-hub-advbox', version: '1.0.0' }.freeze
  INSTRUCTIONS = 'Consulta somente-leitura à gestão processual (AdvBox) da banca Ramon Antônio Advogados. ' \
                 'Datas no formato YYYY-MM-DD. Resultados são JSON cru da API; pagine com "limite" quando a lista vier grande.'.freeze

  LIMITE = { type: 'integer', description: 'Máximo de registros (padrão razoável; use valores pequenos)' }.freeze
  TOOLS = [
    { name: 'advbox_buscar_processos',
      description: 'Busca processos no AdvBox por nome do cliente (parcial), CPF/CNPJ, número do processo, pasta, etapa ou responsável. ' \
                   'Use antes de qualquer consulta que dependa do ID do processo.',
      inputSchema: { type: 'object',
                     properties: { nome: { type: 'string', description: 'Nome (ou parte) do cliente' },
                                   cpf: { type: 'string', description: 'CPF/CNPJ do cliente' },
                                   numero_processo: { type: 'string', description: 'Número exato do processo (CNJ)' },
                                   pasta: { type: 'string' }, etapa: { type: 'string' }, responsavel: { type: 'string' },
                                   limite: LIMITE },
                     required: [] } },
    { name: 'advbox_processo',
      description: 'Dados completos de um processo pelo ID do AdvBox (etapa, responsável, clientes, honorários previstos).',
      inputSchema: { type: 'object', properties: { id: { type: 'integer', description: 'ID do processo no AdvBox' } }, required: ['id'] } },
    { name: 'advbox_movimentacoes',
      description: 'Andamentos/movimentações de um processo, mais recentes primeiro.',
      inputSchema: { type: 'object', properties: { processo_id: { type: 'integer' }, limite: LIMITE }, required: ['processo_id'] } },
    { name: 'advbox_publicacoes',
      description: 'Publicações oficiais (diário) vinculadas a um processo.',
      inputSchema: { type: 'object', properties: { processo_id: { type: 'integer' }, limite: LIMITE }, required: ['processo_id'] } },
    { name: 'advbox_historico_tarefas',
      description: 'Histórico de tarefas já realizadas em um processo.',
      inputSchema: { type: 'object', properties: { processo_id: { type: 'integer' } }, required: ['processo_id'] } },
    { name: 'advbox_ultimas_movimentacoes',
      description: 'Última movimentação de cada processo do escritório — radar do que andou recentemente.',
      inputSchema: { type: 'object', properties: { limite: LIMITE }, required: [] } },
    { name: 'advbox_tarefas',
      description: 'Tarefas do escritório, filtráveis por prazo (prazo_de/prazo_ate), responsável ou processo. ' \
                   'Ex.: prazos da semana = prazo_de segunda + prazo_ate domingo. Aponta prazos; o controle oficial segue no AdvBox.',
      inputSchema: { type: 'object',
                     properties: { processo_id: { type: 'integer' }, responsavel: { type: 'string', description: 'Nome (parcial) do responsável' },
                                   prazo_de: { type: 'string', description: 'YYYY-MM-DD (par com prazo_ate)' },
                                   prazo_ate: { type: 'string', description: 'YYYY-MM-DD' },
                                   data_de: { type: 'string', description: 'Data da tarefa, YYYY-MM-DD (par com data_ate)' },
                                   data_ate: { type: 'string', description: 'YYYY-MM-DD' },
                                   limite: LIMITE },
                     required: [] } },
    { name: 'advbox_buscar_clientes',
      description: 'Busca contatos/clientes por nome (parcial), CPF/CNPJ, telefone ou cidade.',
      inputSchema: { type: 'object',
                     properties: { nome: { type: 'string' }, cpf: { type: 'string' }, telefone: { type: 'string' },
                                   cidade: { type: 'string' }, limite: LIMITE },
                     required: [] } },
    { name: 'advbox_cliente',
      description: 'Ficha completa de um cliente pelo ID do AdvBox.',
      inputSchema: { type: 'object', properties: { id: { type: 'integer', description: 'ID do contato no AdvBox' } }, required: ['id'] } }
  ].freeze

  PROCESSO_FILTROS = { nome: :name, cpf: :identification, numero_processo: :process_number,
                       pasta: :folder, etapa: :stage, responsavel: :responsible }.freeze
  TAREFA_FILTROS = { processo_id: :lawsuit_id, responsavel: :user_name, prazo_de: :deadline_start,
                     prazo_ate: :deadline_end, data_de: :date_start, data_ate: :date_end }.freeze
  CLIENTE_FILTROS = { nome: :name, cpf: :identification, telefone: :phone, cidade: :city }.freeze

  FETCHERS = {
    'advbox_buscar_processos' => ->(a) { Ramon::AdvboxClient.lawsuits(filtros(a, PROCESSO_FILTROS).merge(limit: a.fetch('limite', 20))) },
    'advbox_processo' => ->(a) { Ramon::AdvboxClient.lawsuit(a.fetch('id')) },
    'advbox_movimentacoes' => ->(a) { Ramon::AdvboxClient.movements(a.fetch('processo_id'), limit: a.fetch('limite', 10)) },
    'advbox_publicacoes' => ->(a) { Ramon::AdvboxClient.publications(a.fetch('processo_id'), limit: a.fetch('limite', 5)) },
    'advbox_historico_tarefas' => ->(a) { Ramon::AdvboxClient.history(a.fetch('processo_id')) },
    'advbox_ultimas_movimentacoes' => ->(a) { Ramon::AdvboxClient.last_movements(limit: a.fetch('limite', 20)) },
    'advbox_tarefas' => ->(a) { Ramon::AdvboxClient.posts(filtros(a, TAREFA_FILTROS).merge(limit: a.fetch('limite', 50))) },
    'advbox_buscar_clientes' => ->(a) { Ramon::AdvboxClient.customers(filtros(a, CLIENTE_FILTROS).merge(limit: a.fetch('limite', 20))) },
    'advbox_cliente' => ->(a) { Ramon::AdvboxClient.customer(a.fetch('id')) }
  }.freeze

  def self.handle(message)
    return nil unless message.is_a?(Hash) && message.key?('id')

    case message['method']
    when 'initialize' then reply(message, initialize_result(message))
    when 'ping' then reply(message, {})
    when 'tools/list' then reply(message, { tools: TOOLS })
    when 'tools/call' then reply(message, call_tool(message))
    else error_reply(message, -32_601, "Método não suportado: #{message['method']}")
    end
  end

  def self.initialize_result(message)
    requested = message.dig('params', 'protocolVersion')
    { protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
      capabilities: { tools: { listChanged: false } },
      serverInfo: SERVER_INFO,
      instructions: INSTRUCTIONS }
  end

  # Erro de FERRAMENTA (AdvBox fora do ar, argumento faltando) vira resultado
  # com isError — o protocolo reserva o erro JSON-RPC para falha do protocolo.
  def self.call_tool(message)
    fetcher = FETCHERS.fetch(message.dig('params', 'name')) { raise KeyError, "ferramenta desconhecida: #{message.dig('params', 'name')}" }
    data = fetcher.call(message.dig('params', 'arguments') || {})
    { content: [{ type: 'text', text: JSON.generate(data) }], isError: false }
  rescue KeyError => e
    { content: [{ type: 'text', text: "Argumento inválido — #{e.message}" }], isError: true }
  rescue Ramon::AdvboxClient::UnavailableError => e
    { content: [{ type: 'text', text: e.message }], isError: true }
  end

  def self.filtros(args, mapping)
    mapping.each_with_object({}) do |(pt, api), query|
      value = args[pt.to_s]
      query[api] = value if value.present?
    end
  end

  def self.reply(message, result)
    { jsonrpc: '2.0', id: message['id'], result: result }
  end

  def self.error_reply(message, code, text)
    { jsonrpc: '2.0', id: message['id'], error: { code: code, message: text } }
  end
end
