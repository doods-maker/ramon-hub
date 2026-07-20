# Servidor MCP (Model Context Protocol) mínimo sobre a API do AdvBox, para os
# custom connectors dos projetos Claude Cowork da banca (item 29 do plano
# mestre). Transporte streamable HTTP sem SSE: cada POST JSON-RPC recebe uma
# resposta JSON única; GET (stream) responde 405 no controller. v1.1 (fase 2,
# escopo aprovado pelo Eduardo 17/07/2026): além da leitura, expõe TODA a
# escrita que a API oferece — tarefa, movimentação, cliente, processo
# (criar/editar) e transação financeira (criar/editar). A API não tem
# concluir/editar/apagar tarefa nem delete de nada.
class Ramon::AdvboxMcpService
  PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
  SERVER_INFO = { name: 'ramon-hub-advbox', version: '1.2.0' }.freeze
  INSTRUCTIONS = 'Consulta e escrita na gestão processual (AdvBox) da banca Ramon Antônio Advogados. ' \
                 'Datas no formato YYYY-MM-DD. Resultados são JSON cru da API; pagine com "limite" quando a lista vier grande. ' \
                 'As ferramentas advbox_criar_*/advbox_editar_* gravam DE VERDADE no AdvBox: antes de usar, chame advbox_configuracoes ' \
                 'para obter os IDs (responsável, etapa, tipos, origem, contas) e confirme os dados com o usuário.'.freeze

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
      inputSchema: { type: 'object', properties: { id: { type: 'integer', description: 'ID do contato no AdvBox' } }, required: ['id'] } },
    { name: 'advbox_configuracoes',
      description: 'IDs de configuração da conta AdvBox: usuários, origens de cliente, tipos de tarefa, etapas, tipos de processo e ' \
                   'financeiro (contas, categorias, centros de custo). Consulte SEMPRE antes de qualquer advbox_criar_*/advbox_editar_*.',
      inputSchema: { type: 'object', properties: {}, required: [] } },
    { name: 'advbox_criar_tarefa',
      description: 'Cria uma tarefa num processo do AdvBox. IDs vêm de advbox_configuracoes (tipo_tarefa_id = tasks; responsavel_id = users). ' \
                   'Com hora_inicio a tarefa entra no calendário/agenda do AdvBox (ex.: reunião com horário marcado).',
      inputSchema: { type: 'object',
                     properties: { processo_id: { type: 'integer' }, tipo_tarefa_id: { type: 'integer' },
                                   responsavel_id: { type: 'integer', description: 'Usuário responsável pela tarefa' },
                                   criador_id: { type: 'integer',
                                                 description: 'Quem está criando a tarefa (from). Identifique quem está falando com você ' \
                                                              'batendo o nome com os users de advbox_configuracoes; pergunte se houver ' \
                                                              'dúvida. Padrão: o responsável.' },
                                   data: { type: 'string', description: 'Início, YYYY-MM-DD (padrão: hoje)' },
                                   hora_inicio: { type: 'string', description: 'HH:MM — com hora a tarefa cai no calendário' },
                                   hora_fim: { type: 'string', description: 'HH:MM — término (no mesmo dia do início)' },
                                   prazo: { type: 'string', description: 'Prazo fatal, YYYY-MM-DD' },
                                   descricao: { type: 'string' }, urgente: { type: 'boolean' }, importante: { type: 'boolean' } },
                     required: %w[processo_id tipo_tarefa_id responsavel_id] } },
    { name: 'advbox_criar_movimentacao',
      description: 'Registra uma movimentação/andamento manual num processo (mínimo 10 caracteres na descrição).',
      inputSchema: { type: 'object',
                     properties: { processo_id: { type: 'integer' }, descricao: { type: 'string', description: 'Mínimo 10 caracteres' },
                                   data: { type: 'string', description: 'YYYY-MM-DD (padrão: hoje)' } },
                     required: %w[processo_id descricao] } },
    { name: 'advbox_criar_cliente',
      description: 'Cria um contato/cliente no AdvBox. Antes de criar, use advbox_buscar_clientes para não duplicar.',
      inputSchema: { type: 'object',
                     properties: { nome: { type: 'string' }, responsavel_id: { type: 'integer' },
                                   origem_id: { type: 'integer', description: 'Origem do cliente (origins em advbox_configuracoes)' },
                                   cpf: { type: 'string' }, celular: { type: 'string', description: 'DDD+número, sem +55' },
                                   email: { type: 'string' }, nascimento: { type: 'string', description: 'YYYY-MM-DD' },
                                   cidade: { type: 'string' }, estado: { type: 'string' }, notas: { type: 'string' } },
                     required: %w[nome responsavel_id origem_id] } },
    { name: 'advbox_criar_processo',
      description: 'Cria um processo/caso no AdvBox vinculado a cliente(s) já existentes. Confira antes com advbox_buscar_processos se já existe.',
      inputSchema: { type: 'object',
                     properties: { cliente_ids: { type: 'array', items: { type: 'integer' }, description: 'IDs dos clientes (mínimo 1)' },
                                   responsavel_id: { type: 'integer' }, etapa_id: { type: 'integer' }, tipo_id: { type: 'integer' },
                                   numero_processo: { type: 'string', description: 'Número CNJ, se já judicializado' },
                                   pasta: { type: 'string' }, data: { type: 'string', description: 'YYYY-MM-DD' },
                                   honorarios_previstos: { type: 'number' }, notas: { type: 'string' } },
                     required: %w[cliente_ids responsavel_id etapa_id tipo_id] } },
    { name: 'advbox_editar_processo',
      description: 'Altera um processo existente — mande só os campos que mudam (etapa, responsável, número, honorários etc.).',
      inputSchema: { type: 'object',
                     properties: { id: { type: 'integer' }, responsavel_id: { type: 'integer' }, etapa_id: { type: 'integer' },
                                   tipo_id: { type: 'integer' }, numero_processo: { type: 'string' }, pasta: { type: 'string' },
                                   data: { type: 'string', description: 'YYYY-MM-DD' }, honorarios_previstos: { type: 'number' },
                                   notas: { type: 'string' } },
                     required: ['id'] } },
    { name: 'advbox_criar_transacao',
      description: 'Lança uma transação financeira (receita ou despesa). IDs de conta/categoria/centro de custo em advbox_configuracoes ' \
                   '(financial); a categoria precisa ser do mesmo tipo (receita/despesa) da transação.',
      inputSchema: { type: 'object',
                     properties: { tipo: { type: 'string', enum: %w[receita despesa] }, valor: { type: 'number' },
                                   vencimento: { type: 'string', description: 'YYYY-MM-DD' }, responsavel_id: { type: 'integer' },
                                   conta_id: { type: 'integer', description: 'Conta bancária (banks)' }, categoria_id: { type: 'integer' },
                                   centro_custo_id: { type: 'integer' }, cliente_id: { type: 'integer' },
                                   processo_id: { type: 'integer', description: 'Exige cliente_id junto' },
                                   descricao: { type: 'string' },
                                   data_pagamento: { type: 'string', description: 'YYYY-MM-DD, não pode ser futura' } },
                     required: %w[tipo valor vencimento responsavel_id conta_id categoria_id centro_custo_id] } },
    { name: 'advbox_editar_transacao',
      description: 'Altera uma transação financeira existente — mande só os campos que mudam (valor, vencimento, pagamento etc.). ' \
                   'Ao trocar categoria_id, mande tipo junto (a API valida o par). Não dá para reabrir transação paga por aqui ' \
                   '(limpar data_pagamento exige null explícito, não suportado).',
      inputSchema: { type: 'object',
                     properties: { id: { type: 'integer' }, tipo: { type: 'string', enum: %w[receita despesa] }, valor: { type: 'number' },
                                   vencimento: { type: 'string', description: 'YYYY-MM-DD' }, responsavel_id: { type: 'integer' },
                                   conta_id: { type: 'integer' }, categoria_id: { type: 'integer' }, centro_custo_id: { type: 'integer' },
                                   cliente_id: { type: 'integer' }, processo_id: { type: 'integer' }, descricao: { type: 'string' },
                                   data_pagamento: { type: 'string', description: 'YYYY-MM-DD' } },
                     required: ['id'] } }
  ].each { |t| t[:inputSchema][:additionalProperties] = false }.freeze

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
    'advbox_cliente' => ->(a) { Ramon::AdvboxClient.customer(a.fetch('id')) },
    'advbox_configuracoes' => ->(_a) { Ramon::AdvboxClient.settings },
    'advbox_criar_tarefa' => ->(a) { Ramon::AdvboxClient.create_post(tarefa_payload(a)) },
    'advbox_criar_movimentacao' => lambda { |a|
      Ramon::AdvboxClient.create_movement(lawsuit_id: a.fetch('processo_id'), description: a.fetch('descricao'),
                                          date: data_br(a['data'].presence || Time.zone.today.iso8601))
    },
    'advbox_criar_cliente' => ->(a) { Ramon::AdvboxClient.create_customer(cliente_payload(a)) },
    'advbox_criar_processo' => ->(a) { Ramon::AdvboxClient.create_lawsuit(processo_payload(a).merge(customers_id: a.fetch('cliente_ids'))) },
    'advbox_editar_processo' => ->(a) { Ramon::AdvboxClient.update_lawsuit(a.fetch('id'), processo_payload(a)) },
    'advbox_criar_transacao' => ->(a) { Ramon::AdvboxClient.create_transaction(transacao_payload(a)) },
    'advbox_editar_transacao' => ->(a) { Ramon::AdvboxClient.update_transaction(a.fetch('id'), transacao_payload(a)) }
  }.freeze
  ESCRITAS = FETCHERS.keys.grep(/criar|editar/).freeze

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
    requested = message['params'].is_a?(Hash) ? message['params']['protocolVersion'] : nil
    { protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
      capabilities: { tools: { listChanged: false } },
      serverInfo: SERVER_INFO,
      instructions: INSTRUCTIONS }
  end

  # Erro de FERRAMENTA (AdvBox fora do ar, argumento faltando) vira resultado
  # com isError — o protocolo reserva o erro JSON-RPC para falha do protocolo.
  def self.call_tool(message)
    params = message['params'].is_a?(Hash) ? message['params'] : {}
    name = params['name']
    args = params['arguments'].is_a?(Hash) ? params['arguments'] : {}
    fetcher = FETCHERS.fetch(name) { raise KeyError, "ferramenta desconhecida: #{name}" }
    Rails.logger.info("AdvboxMcp escrita: #{name} #{args.to_json}") if ESCRITAS.include?(name)
    { content: [{ type: 'text', text: JSON.generate(fetcher.call(args)) }], isError: false }
  rescue Date::Error
    { content: [{ type: 'text', text: 'Data inválida — use o formato YYYY-MM-DD' }], isError: true }
  rescue KeyError, ArgumentError, TypeError, NoMethodError => e
    # TypeError/NoMethodError: o server não valida inputSchema — argumento de
    # tipo errado (valor booleano, celular numérico) tem que virar isError, não 500.
    { content: [{ type: 'text', text: "Argumento inválido — #{e.message}" }], isError: true }
  rescue Ramon::AdvboxClient::RequestError => e
    { content: [{ type: 'text', text: "AdvBox recusou (HTTP #{e.code}): #{e.body.to_json}" }], isError: true }
  rescue Ramon::AdvboxClient::UnavailableError => e
    { content: [{ type: 'text', text: e.message }], isError: true }
  end

  def self.filtros(args, mapping)
    mapping.each_with_object({}) do |(pt, api), query|
      value = args[pt.to_s]
      query[api] = value if value.present?
    end
  end

  def self.tarefa_payload(args)
    responsavel = args.fetch('responsavel_id')
    inicio = args['data'].presence || Time.zone.today.iso8601
    { from: (args['criador_id'] || responsavel).to_s, guests: [responsavel], tasks_id: args.fetch('tipo_tarefa_id').to_s,
      lawsuits_id: args.fetch('processo_id').to_s, start_date: inicio,
      start_time: args['hora_inicio'].presence,
      # A API ignora end_time sem end_date — tarefa com hora é sempre no mesmo dia.
      end_time: args['hora_fim'].presence, end_date: args['hora_fim'].presence && inicio,
      date_deadline: args['prazo'], comments: args['descricao'],
      urgent: args['urgente'], important: args['importante'] }.compact
  end

  def self.cliente_payload(args)
    { users_id: args.fetch('responsavel_id'), customers_origins_id: args.fetch('origem_id'), name: args.fetch('nome'),
      identification: args['cpf'], cellphone: args['celular']&.delete('^0-9'), email: args['email'],
      birthdate: args['nascimento'], city: args['cidade'], state: args['estado'], notes: args['notas'] }.compact
  end

  # Campos comuns a criar/editar processo — cliente_ids (obrigatório só no
  # criar) entra no chamador; no editar, só o que vier no argumento.
  def self.processo_payload(args)
    { users_id: args['responsavel_id'], stages_id: args['etapa_id'], type_lawsuits_id: args['tipo_id'],
      process_number: args['numero_processo'], folder: args['pasta'], date: args['data'],
      fees_expec: args['honorarios_previstos'], notes: args['notas'] }.compact
  end

  TIPO_TRANSACAO = { 'receita' => 'income', 'despesa' => 'expense' }.freeze

  def self.transacao_payload(args)
    { entry_type: args['tipo'] && TIPO_TRANSACAO.fetch(args['tipo']), amount: args['valor'] && format('%.2f', Float(args['valor'])).tr('.', ','),
      date_due: args['vencimento'], users_id: args['responsavel_id'], debit_account: args['conta_id'],
      categories_id: args['categoria_id'], cost_centers_id: args['centro_custo_id'], customers_id: args['cliente_id'],
      lawsuits_id: args['processo_id'], description: args['descricao'], date_payment: args['data_pagamento'] }.compact
  end

  # A API de movimentação é a única que exige DD/MM/YYYY.
  def self.data_br(iso)
    Date.iso8601(iso).strftime('%d/%m/%Y')
  end

  def self.reply(message, result)
    { jsonrpc: '2.0', id: message['id'], result: result }
  end

  def self.error_reply(message, code, text)
    { jsonrpc: '2.0', id: message['id'], error: { code: code, message: text } }
  end
end
