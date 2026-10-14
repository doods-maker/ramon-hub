# Consulta de andamento (ADR 0008): quem diz que já é cliente informa CPF + data de nascimento; só com os dois
# conferindo no cadastro do ADVBOX a tool devolve a fase de cada processo em linguagem simples — a mesma regra do
# Painel do Cliente e da Conferência de fases (Ramon::PortalTexto.etapa_real: tribunal + tarefas, nunca a etapa do
# ADVBOX) — e o link do Painel. CPF e nascimento são usados na hora: não vão pro lead/contato, nem pro log, nem pra
# tela Execuções.
# ponytail: ao vivo, 2 chamadas ao ADVBOX por processo (andamentos + tarefas), dividindo o limite de 500/dia/rota
# com a Conferência de fases da noite; se apertar, ler o espelho do Painel (PortalCliente#processos) primeiro.
class Captain::Tools::ConsultaAndamentoTool < Captain::Tools::BasePublicTool
  T = Ramon::PortalTexto
  SYNC = Ramon::PortalSyncService
  NAO_CONFERIU = 'NAO CONFERIU: os dados nao conferem com o cadastro do escritorio. Nao diga qual dos dois nao bateu; ' \
                 'passe para humano.'.freeze
  SEM_PROCESSO = 'Conferiu, mas nao ha processo no AdvBox para este cliente. Passe para humano.'.freeze
  ADVBOX_FORA = 'O AdvBox nao respondeu agora. Passe para humano.'.freeze
  SEM_PAINEL = 'Este cliente ainda nao tem acesso ao Painel do Cliente: nao mande o link.'.freeze
  JA_CLIENTE = 'Já é cliente'.freeze

  description 'Consulta de andamento para quem ja e cliente: confere CPF + data de nascimento no cadastro do escritorio ' \
              'e devolve a fase de cada processo em linguagem simples e o link do Painel do Cliente. Nao conferiu: humano.'
  param :cpf, type: 'string', desc: 'CPF informado pelo cliente, com ou sem pontuacao', required: true
  param :nascimento, type: 'string', desc: 'Data de nascimento informada pelo cliente, AAAA-MM-DD', required: true

  def perform(tool_context, cpf:, nascimento:)
    digitos = cpf.to_s.delete('^0-9')
    conferiu = digitos.size == 11 && cadastro_confere?(digitos, data(nascimento))
    log_tool_usage('consulta_andamento', { conferiu: conferiu })
    return NAO_CONFERIU unless conferiu

    marcar_cliente(tool_context)
    processos = lista(Ramon::AdvboxClient.lawsuits(identification: digitos, limit: SYNC::LIMITE_PROCESSOS))
    return SEM_PROCESSO if processos.empty?

    "Conferiu. Fase de cada processo (a mesma do Painel do Cliente):\n#{processos.map { |l| linha(l) }.join("\n")}\n#{painel(digitos)}"
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    ADVBOX_FORA
  end

  private

  # Execuções guarda só os nomes dos campos: CPF e nascimento nunca ficam gravados.
  def registrar_execucao(tool_context, params, *)
    super(tool_context, params.transform_values { '[oculto]' }, *)
  end

  # Conferiu: o lead que a conversa abriu é de cliente → Perdido "Já é cliente" (funil e métricas sem cliente).
  def marcar_cliente(tool_context)
    conversa = find_conversation(tool_context&.state)
    lead = conversa && Lead.find_by(account_id: conversa.account_id, conversation_id: conversa.id)
    return if lead.nil? || lead.won_at || lead.lost_at

    perdido = lead.account.lead_stages.find_by(is_lost: true)
    lead.update!(lead_stage: perdido, lost_reason: JA_CLIENTE) if perdido
  end

  # O filtro do ADVBOX pode casar CPF parcial: só vale cadastro com o mesmo CPF e o mesmo nascimento.
  def cadastro_confere?(digitos, nascimento)
    return false if nascimento.nil?

    lista(Ramon::AdvboxClient.customers(identification: digitos)).any? do |c|
      c['identification'].to_s.delete('^0-9') == digitos && data(c['birthdate']) == nascimento
    end
  end

  def linha(lawsuit)
    processo = processo(lawsuit)
    fase = T.fase_de(T.etapa_real(processo), lawsuit['step']) || 'documentos'
    texto = T::V2['fases'].find { |f| f['chave'] == fase }
    "- #{T.identificacao(processo).compact.join(' · ')}: #{texto['nome']} — #{texto['frase']}"
  end

  # O processo no formato do espelho do Painel do Cliente (Ramon::PortalSyncService#espelho + PortalNovidades).
  def processo(lawsuit)
    andamentos = lista(Ramon::AdvboxClient.movements(lawsuit['id'], limit: SYNC::LIMITE_ANDAMENTOS))
                 .map { |m| { 'data' => m['date'].to_s[0, 10], 'titulo' => m['title'] } }
    tarefas = lista(Ramon::AdvboxClient.posts(lawsuit_id: lawsuit['id'], limit: SYNC::LIMITE_TAREFAS))
    { 'numero' => lawsuit['process_number'], 'protocolo' => lawsuit['protocol_number'], 'tipo' => lawsuit['type'],
      'etapa' => lawsuit['stage'], 'fase' => lawsuit['step'], 'andamentos' => andamentos,
      'tribunal' => T.achado_do_tribunal(andamentos), 'agenda' => SYNC.agenda(tarefas), 'docs_pendentes' => pedidos(tarefas) }
  end

  # Pedido de documento aberto (só a presença importa pra fase).
  def pedidos(tarefas)
    tarefas.select { |p| T.normalizar(p['task']).include?(SYNC::TAREFA_SOLICITAR) && SYNC.aberta?(p) && p['notes'].present? }
  end

  # Link só pra quem consegue entrar (mesma regra do login do painel).
  def painel(digitos)
    cliente = @assistant.account.portal_clientes.find_by(cpf: digitos)
    return SEM_PAINEL unless cliente&.convidado_em.present? && !cliente.suspenso?

    "Painel do Cliente (entra com o CPF e a senha dele): #{ENV.fetch('PORTAL_URL', "#{ENV.fetch('FRONTEND_URL', nil)}/cliente")}"
  end

  def data(valor)
    Date.parse(valor.to_s)
  rescue Date::Error
    nil
  end

  # Envelope das listas do ADVBOX: { offset, limit, totalCount, data }.
  def lista(resposta) = Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
end
