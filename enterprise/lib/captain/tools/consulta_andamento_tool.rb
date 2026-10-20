# Consulta de andamento (ADR 0008, revisada 20/10): quem diz que já é cliente informa o CPF; com o CPF conferindo
# no cadastro do ADVBOX a tool devolve a fase de cada processo em linguagem simples — a mesma regra do
# Painel do Cliente e da Conferência de fases (Ramon::PortalTexto.etapa_real: tribunal + tarefas, nunca a etapa do
# ADVBOX) — e o link do Painel. O CPF é usado na hora: não vai pro lead/contato, nem pro log, nem pra tela Execuções.
# ponytail: ao vivo, 2 chamadas ao ADVBOX por processo (andamentos + tarefas), dividindo o limite de 500/dia/rota
# com a Conferência de fases da noite; se apertar, ler o espelho do Painel (PortalCliente#processos) primeiro.
class Captain::Tools::ConsultaAndamentoTool < Captain::Tools::BasePublicTool
  T = Ramon::PortalTexto
  SYNC = Ramon::PortalSyncService
  NAO_CONFERIU = 'NAO CONFERIU: o CPF nao confere com o cadastro do escritorio. Passe para humano.'.freeze
  # 1º desencontro na conversa (decisão Eduardo 20/10): pode ser erro de digitação — pede pra conferir uma vez.
  CONFERIR = 'NAO CONFERIU (1a tentativa): pode ser erro de digitacao. Peca, com simpatia, que a pessoa confira e mande de ' \
             'novo o CPF. Nao passe para humano ainda.'.freeze
  SEM_PROCESSO = 'Conferiu, mas nao ha processo no AdvBox para este cliente. Passe para humano.'.freeze
  ADVBOX_FORA = 'O AdvBox nao respondeu agora. Passe para humano.'.freeze
  SEM_PAINEL = 'Este cliente ainda nao tem acesso ao Painel do Cliente: nao mande o link.'.freeze
  JA_CLIENTE = 'Já é cliente'.freeze
  # 3 conferências que falham por conversa em 1h: para de consultar (enumeração de CPF + cota do ADVBOX).
  LIMITE_FALHAS = 3
  LIMITE = 'LIMITE: tentativas demais nesta conversa, nao consulte de novo. Passe para humano.'.freeze

  description 'Consulta de andamento para quem ja e cliente: confere o CPF no cadastro do escritorio ' \
              'e devolve a fase de cada processo em linguagem simples e o link do Painel do Cliente. Nao conferiu: humano.'
  param :cpf, type: 'string', desc: 'CPF informado pelo cliente, com ou sem pontuacao', required: true

  # ponytail: só o CPF identifica (decisão Eduardo 20/10, risco aceito: quem tiver o CPF de um cliente vê a fase do
  # processo). Endurecer = conferir também o número do WhatsApp com o telefone do cadastro.
  def perform(tool_context, cpf:)
    chave = chave_falhas(tool_context)
    return LIMITE if estourou?(chave)

    digitos = cpf.to_s.delete('^0-9')
    conferiu = digitos.size == 11 && cadastro_confere?(digitos)
    log_tool_usage('consulta_andamento', { conferiu: conferiu })
    return contar_falha(chave) unless conferiu

    marcar_cliente(tool_context)
    processos = lista(Ramon::AdvboxClient.lawsuits(identification: digitos, limit: SYNC::LIMITE_PROCESSOS))
    return SEM_PROCESSO if processos.empty?

    "Conferiu. Fase de cada processo (a mesma do Painel do Cliente):\n#{processos.map { |l| linha(l) }.join("\n")}\n#{painel(digitos)}"
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    ADVBOX_FORA
  end

  private

  # Sem conversa (Testar no hub) não conta.
  def chave_falhas(tool_context)
    id = tool_context&.state&.dig(:conversation, :id)
    "RAMON::CONSULTA_ANDAMENTO::FALHAS::#{id}" if id
  end

  def estourou?(chave) = chave.present? && Redis::Alfred.get(chave).to_i >= LIMITE_FALHAS

  # 1ª falha da conversa: pede pra conferir; da 2ª em diante: humano. Sem conversa (Testar): humano direto.
  def contar_falha(chave)
    return NAO_CONFERIU unless chave

    falhas = Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, 1.hour.to_i) if falhas == 1
    falhas == 1 ? CONFERIR : NAO_CONFERIU
  end

  # Execuções guarda só os nomes dos campos: o CPF nunca fica gravado.
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

  # O filtro do ADVBOX pode casar CPF parcial: só vale cadastro com o mesmo CPF.
  def cadastro_confere?(digitos)
    lista(Ramon::AdvboxClient.customers(identification: digitos)).any? { |c| c['identification'].to_s.delete('^0-9') == digitos }
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

  # Envelope das listas do ADVBOX: { offset, limit, totalCount, data }.
  def lista(resposta) = Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
end
