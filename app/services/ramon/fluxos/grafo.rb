# Desenho de um fluxo: { 'nos' => [{id, tipo, config, posicao}], 'setas' => [{de, saida, para}] }.
# Regras de publicação (spec §5): 1 gatilho; sem ciclo; tudo ligado ao gatilho;
# saídas válidas por tipo; mensagem ao cliente só como rascunho; webhook só como último passo.
class Ramon::Fluxos::Grafo
  class Invalido < StandardError; end

  GATILHOS = %w[conversa_criada mensagem_recebida conversa_resolvida conversa_reaberta conversa_atribuida
                lead_criado lead_mudou_etapa lead_ganho lead_perdido manual
                lead_parado relogio reuniao_marcada reuniao_cancelada reuniao_na_agenda evento_advbox
                contrato_assinado contrato_recusado documento_recebido horario_conta nota_escrita].freeze
  TIPOS_PASSO = %w[se escolha esperar parar rascunho_texto nota_privada acao_chatwoot
                   mover_etapa criar_tarefa avisar_sino avisar_push
                   perguntar_ia rascunho_ia rodar_skill advbox webhook
                   registrar_atividade trocar_responsavel preencher_campo apagar_reuniao registrar_retomada rotina].freeze
  OBRIGATORIOS = {
    'rascunho_texto' => %w[texto], 'nota_privada' => %w[texto], 'mover_etapa' => %w[etapa_id],
    'criar_tarefa' => %w[titulo], 'escolha' => %w[campo], 'avisar_sino' => %w[texto], 'avisar_push' => %w[texto],
    'perguntar_ia' => %w[pergunta], 'rascunho_ia' => %w[instrucao], 'rodar_skill' => %w[assistente_id skill_id],
    'registrar_atividade' => %w[texto], 'trocar_responsavel' => %w[papel], 'rotina' => %w[rotina]
  }.freeze
  # tipo → método com as regras próprias do passo (além dos obrigatórios)
  ESPECIFICOS = {
    'se' => :erros_se, 'perguntar_ia' => :erros_saida, 'escolha' => :erros_escolha, 'esperar' => :erros_esperar,
    'acao_chatwoot' => :erros_chatwoot, 'advbox' => :erros_advbox, 'webhook' => :erros_webhook, 'preencher_campo' => :erros_campo
  }.freeze
  NOMES = { 'se' => 'Se', 'perguntar_ia' => 'Perguntar à IA' }.freeze
  HORA = /\A([01]\d|2[0-3]):[0-5]\d\z/
  CHAVE_CAMPO = /\A[a-z][a-z0-9_]{0,39}\z/
  MENSAGEM_CLIENTE = %w[send_message send_attachment].freeze
  # sem envio externo: transcript pode ir pro e-mail do contato; webhook vira passo próprio (B2b)
  PROIBIDAS_CHATWOOT = (MENSAGEM_CLIENTE + %w[send_email_transcript send_webhook_event]).freeze

  attr_reader :nos, :setas

  # Allowlist: só o que a regra do Chatwoot aceita (inclui as do enterprise), menos as proibidas —
  # o ActionService chama o nome da ação com `send`, então nome livre seria execução arbitrária.
  # Sob demanda: AutomationRule.new lê o schema, e o assets:precompile do Docker roda sem banco.
  def self.permitidas_chatwoot = @permitidas_chatwoot ||= (AutomationRule.new.actions_attributes - PROIBIDAS_CHATWOOT).freeze

  def initialize(dados)
    dados = (dados || {}).to_h.deep_stringify_keys
    @nos = Array(dados['nos'])
    @setas = Array(dados['setas'])
  end

  def no(id) = nos.find { |n| n['id'] == id }

  def gatilho = nos.find { |n| n['tipo'] == 'gatilho' }

  def proximo(id, saida) = setas.find { |s| s['de'] == id && s['saida'] == saida }&.dig('para')

  def erros
    e = erros_gatilho
    return e if e.any?

    e + erros_setas + erros_alcance + nos.flat_map { |n| erros_passo(n) } + Ramon::Fluxos::HorarioConta.erros(self) # B5
  end

  private

  def erros_gatilho
    gatilhos = nos.select { |n| n['tipo'] == 'gatilho' }
    return ['O fluxo precisa de exatamente 1 gatilho'] unless gatilhos.one?

    config = gatilhos.first['config'] || {}
    return ["Gatilho desconhecido: #{config['tipo']}"] unless GATILHOS.include?(config['tipo'])

    erros_hora(config)
  end

  # relógio exige a hora; lead parado usa 11:00 (Relogio::HORA_PADRAO) se vier vazia
  def erros_hora(config)
    hora = config['hora'].to_s
    return ['O relógio precisa da hora (HH:MM)'] if config['tipo'] == 'relogio' && hora.empty?

    hora.empty? || hora.match?(HORA) ? [] : ['Hora do gatilho inválida (use HH:MM)']
  end

  def erros_setas
    ids = nos.pluck('id')
    fantasmas = setas.flat_map { |s| [s['de'], s['para']] }.uniq - ids
    erros = fantasmas.map { |id| "Seta aponta para passo inexistente: #{id}" }
    repetidas = setas.group_by { |s| [s['de'], s['saida']] }.select { |_, v| v.size > 1 }.keys
    erros + repetidas.map { |de, saida| "Passo #{de}: mais de uma seta na saída #{saida}" }
  end

  def erros_alcance
    return ['O fluxo não pode voltar para um passo anterior'] if ciclo?

    alcancados = alcancaveis(gatilho['id'])
    nos.reject { |n| alcancados.include?(n['id']) }.map { |n| "Passo #{n['id']} não está ligado ao gatilho" }
  end

  def alcancaveis(inicio)
    vistos = Set.new
    fila = [inicio]
    while (id = fila.shift)
      next unless vistos.add?(id)

      fila.concat(setas.select { |s| s['de'] == id }.pluck('para'))
    end
    vistos
  end

  def ciclo?
    estado = {}
    visita = lambda do |id|
      return true if estado[id] == :aberto
      return false if estado[id] == :fechado

      estado[id] = :aberto
      achou = setas.select { |s| s['de'] == id }.any? { |s| visita.call(s['para']) }
      estado[id] = :fechado
      achou
    end
    nos.any? { |n| visita.call(n['id']) }
  end

  def erros_passo(passo)
    return [] if passo['tipo'] == 'gatilho'
    return ["Passo #{passo['id']}: tipo desconhecido (#{passo['tipo']})"] unless TIPOS_PASSO.include?(passo['tipo'])

    config = passo['config'] || {}
    erros = Array(OBRIGATORIOS[passo['tipo']]).select { |k| config[k].blank? }.map { |k| "Passo #{passo['id']}: falta #{k}" }
    erros + erros_especificos(passo, config)
  end

  def erros_especificos(passo, config)
    metodo = ESPECIFICOS[passo['tipo']]
    metodo ? send(metodo, passo, config) : []
  end

  def erros_se(passo, config)
    erros = Array(config['condicoes']).empty? ? ["Passo #{passo['id']} (Se) precisa de condições"] : []
    horarios = Array(config['condicoes']).select { |c| c['operador'] == 'em_horario_comercial' }
    erros + horarios.flat_map { |c| erros_janela(passo, c) } + erros_saida(passo, config)
  end

  def erros_saida(passo, _config)
    return [] if setas.any? { |s| s['de'] == passo['id'] }

    ["Passo #{passo['id']} (#{NOMES[passo['tipo']]}) precisa de pelo menos uma saída"]
  end

  def erros_esperar(passo, config)
    erros = espera_valida?(config) ? [] : ["Passo #{passo['id']}: falta o tempo de espera"]
    config['ate'] == 'horario_comercial' ? erros + erros_janela(passo, config) : erros
  end

  # B4.2: janela de horário do próprio passo (Ramon::Fluxos::Horario.janela_valida?)
  def erros_janela(passo, config)
    Ramon::Fluxos::Horario.janela_valida?(config) ? [] : ["Passo #{passo['id']}: horário inválido (dias e início antes do fim)"]
  end

  # IDs fixos escolhidos na tela (advbox_configuracoes) — escrita determinística, não é a IA decidindo
  def erros_advbox(passo, config)
    id = passo['id']
    case config['acao']
    when 'tarefa' then %w[tipo_tarefa_id responsavel_id].select { |k| config[k].blank? }.map { |k| "Passo #{id}: falta #{k}" }
    when 'movimentacao'
      config['descricao'].to_s.strip.length >= 10 ? [] : ["Passo #{id}: a movimentação do ADVBOX precisa de pelo menos 10 letras"]
    else ["Passo #{id}: escolha tarefa ou movimentação do ADVBOX"]
    end
  end

  # regra do Flowter: webhook só no fim; https só (o SafeFetch ainda barra rede interna na hora de rodar)
  def erros_webhook(passo, config)
    erros = []
    erros << "Passo #{passo['id']}: o webhook precisa de um endereço https://" unless config['url'].to_s.start_with?('https://')
    erros << "Passo #{passo['id']} (Webhook) tem que ser o último passo" if setas.any? { |s| s['de'] == passo['id'] }
    erros
  end

  def erros_campo(passo, config)
    chave = config['chave'].to_s
    return ["Passo #{passo['id']}: nome do campo só com letras minúsculas, números e _ (até 40)"] unless chave.match?(CHAVE_CAMPO)

    Ramon::Fluxos::Contexto::RESERVADAS.include?(chave) ? ["Passo #{passo['id']}: #{chave} é um nome reservado do hub"] : []
  end

  def erros_escolha(passo, config)
    casos = Array(config['casos'])
    return ["Passo #{passo['id']} (Escolha) precisa de pelo menos 2 casos"] if casos.size < 2

    erros = []
    erros << "Passo #{passo['id']} (Escolha): casos com a mesma chave" if casos.pluck('chave').uniq.size < casos.size
    valores = casos.flat_map { |c| Array(c['valores']).map { |v| v.to_s.downcase } }
    erros << "Passo #{passo['id']} (Escolha): o mesmo valor em dois casos" if valores.uniq.size < valores.size
    erros
  end

  def espera_valida?(config)
    config['ate'] == 'horario_comercial' || (config['desde'] == 'conversa' && config['prazo'] == 'sla_caixa') ||
      (config['quantidade'].to_i.positive? && %w[minutos horas dias].include?(config['unidade']))
  end

  def erros_chatwoot(passo, config)
    nomes = Array(config['acoes']).pluck('action_name')
    return ["Passo #{passo['id']}: escolha pelo menos uma ação"] if nomes.empty?
    return ["Passo #{passo['id']}: mensagem ao cliente só como rascunho"] if nomes.intersect?(MENSAGEM_CLIENTE)

    nomes.filter_map do |nome|
      if PROIBIDAS_CHATWOOT.include?(nome) then "Passo #{passo['id']}: ação não permitida no fluxo (#{nome})"
      elsif self.class.permitidas_chatwoot.exclude?(nome) then "Passo #{passo['id']}: ação desconhecida (#{nome})"
      end
    end
  end
end
