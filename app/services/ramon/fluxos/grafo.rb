# Desenho de um fluxo: { 'nos' => [{id, tipo, config, posicao}], 'setas' => [{de, saida, para}] }.
# Regras de publicação (spec §5): 1 gatilho; sem ciclo; tudo ligado ao gatilho;
# saídas válidas por tipo; mensagem ao cliente só como rascunho.
class Ramon::Fluxos::Grafo
  class Invalido < StandardError; end

  GATILHOS = %w[conversa_criada mensagem_recebida conversa_resolvida conversa_reaberta conversa_atribuida
                lead_criado lead_mudou_etapa lead_ganho lead_perdido manual].freeze
  TIPOS_PASSO = %w[se escolha esperar parar rascunho_texto nota_privada acao_chatwoot
                   mover_etapa criar_tarefa avisar_sino avisar_push].freeze
  OBRIGATORIOS = {
    'rascunho_texto' => %w[texto], 'nota_privada' => %w[texto], 'mover_etapa' => %w[etapa_id],
    'criar_tarefa' => %w[titulo], 'escolha' => %w[campo], 'avisar_sino' => %w[texto], 'avisar_push' => %w[texto]
  }.freeze
  PROIBIDAS_CHATWOOT = %w[send_message send_attachment].freeze

  attr_reader :nos, :setas

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

    e + erros_setas + erros_alcance + nos.flat_map { |n| erros_passo(n) }
  end

  private

  def erros_gatilho
    gatilhos = nos.select { |n| n['tipo'] == 'gatilho' }
    return ['O fluxo precisa de exatamente 1 gatilho'] unless gatilhos.one?

    tipo = gatilhos.first.dig('config', 'tipo')
    GATILHOS.include?(tipo) ? [] : ["Gatilho desconhecido: #{tipo}"]
  end

  def erros_setas
    ids = nos.map { |n| n['id'] }
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

  def erros_passo(no)
    return [] if no['tipo'] == 'gatilho'
    return ["Passo #{no['id']}: tipo desconhecido (#{no['tipo']})"] unless TIPOS_PASSO.include?(no['tipo'])

    config = no['config'] || {}
    erros = Array(OBRIGATORIOS[no['tipo']]).select { |k| config[k].blank? }.map { |k| "Passo #{no['id']}: falta #{k}" }
    erros + erros_especificos(no, config)
  end

  def erros_especificos(no, config)
    case no['tipo']
    when 'se' then erros_se(no, config)
    when 'escolha' then erros_escolha(no, config)
    when 'esperar' then espera_valida?(config) ? [] : ["Passo #{no['id']}: falta o tempo de espera"]
    when 'acao_chatwoot' then erros_chatwoot(no, config)
    else []
    end
  end

  def erros_se(no, config)
    erros = []
    erros << "Passo #{no['id']} (Se) precisa de condições" if Array(config['condicoes']).empty?
    erros << "Passo #{no['id']} (Se) precisa de pelo menos uma saída" if setas.none? { |s| s['de'] == no['id'] }
    erros
  end

  def erros_escolha(no, config)
    casos = Array(config['casos'])
    return ["Passo #{no['id']} (Escolha) precisa de pelo menos 2 casos"] if casos.size < 2

    erros = []
    erros << "Passo #{no['id']} (Escolha): casos com a mesma chave" if casos.pluck('chave').uniq.size < casos.size
    valores = casos.flat_map { |c| Array(c['valores']).map { |v| v.to_s.downcase } }
    erros << "Passo #{no['id']} (Escolha): o mesmo valor em dois casos" if valores.uniq.size < valores.size
    erros
  end

  def espera_valida?(config)
    config['ate'] == 'horario_comercial' ||
      (config['quantidade'].to_i.positive? && %w[minutos horas dias].include?(config['unidade']))
  end

  def erros_chatwoot(no, config)
    nomes = Array(config['acoes']).map { |a| a['action_name'] }
    return ["Passo #{no['id']}: escolha pelo menos uma ação"] if nomes.empty?

    (nomes & PROIBIDAS_CHATWOOT).any? ? ["Passo #{no['id']}: mensagem ao cliente só como rascunho"] : []
  end
end
