# Transforma um evento (ou um clique) em execuções de fluxo (spec §6): acha os fluxos
# ativos com aquele gatilho, aplica o filtro, o limite do dia e a profundidade de cadeia,
# e cria a execução — o índice único parcial barra 2 execuções vivas no mesmo alvo.
# Toda execução nasce 'esperando' e vencida: o Executor a reivindica (ensaio: na hora).
class Ramon::Fluxos::Disparo
  PROFUNDIDADE_MAX = 3
  # B4.1: a mesma reunião de novo na agenda (remarcada) cancela a espera do ciclo dela e recomeça pelo horário novo.
  RECOMECA = %w[reuniao_na_agenda].freeze
  # B4.1: os fluxos migrados de marcar/cancelar rodam na hora, dentro da requisição (o painel vê a tarefa ao recarregar;
  # em sombra, o ensaio vê o lead antes de o código mexer). B4.5: o de eventos do ADVBOX também, dentro do job do ADVBOX —
  # a execução vive só enquanto roda, então dois eventos seguidos do mesmo lead quase nunca se barram no índice único.
  # Só os migrados: fluxo comum nesses gatilhos segue pelo job, como sempre.
  NA_HORA = %w[reuniao_marcada reuniao_cancelada evento_advbox].freeze
  # B5-leads: fluxos migrados que rodam na hora pela CHAVE do fluxo (não pelo gatilho — o SLA, o coach e a sugestão de
  # documento dividem os gatilhos e seguem pelo job): o lead criado e a origem gravada precisam existir antes do SLA e
  # dos fluxos comuns do mesmo evento — a ordem de sempre.
  NA_HORA_CHAVES = %w[criar_lead_da_conversa origem_do_lead].freeze
  # B4.1/B4.2/B4.4: gatilhos que o código dispara 2 vezes — com 'assumido' (a decisão do evento) só os fluxos migrados ouvem;
  # sem (o ouvinte de sempre), só os demais. conversa_criada: o RamonLeadListener manda a decisão do SLA da 1ª resposta;
  # lead_ganho: o callback do Lead (Ramon::Fluxos::LeadGanho) manda com, o RamonFluxoListener sem.
  # B5-leads: mensagem_recebida (origem, documento, coach) e nota_escrita (agente); 'migracao' no evento separa os grupos.
  # B5-externos: os gatilhos de fora do funil (Ramon::Fluxos::Externos.evento manda com e sem a decisão).
  DUAS_VEZES = (NA_HORA + %w[conversa_criada lead_ganho mensagem_recebida nota_escrita] + Ramon::Fluxos::Externos.gatilhos).freeze

  def self.call(gatilho_tipo, alvo, dados = {}, origem: nil)
    account = alvo.account
    account.fluxos.executaveis.where(gatilho_tipo: gatilho_tipo).includes(:versao_publicada).filter_map do |fluxo|
      new(fluxo, alvo, dados, origem).iniciar if da_vez?(fluxo, dados) && passa?(fluxo, dados, origem)
    end
  end

  def self.manual(fluxo, alvo)
    # desligado não roda: o Executor cancelaria na hora ("o fluxo foi desligado")
    return unless fluxo.ativo && fluxo.gatilho_tipo == 'manual' && fluxo.versao_publicada && !fluxo.limite_atingido?

    new(fluxo, alvo, {}, nil).iniciar
  end

  def self.ensaiar(fluxo, alvo, usar: 'rascunho')
    new(fluxo, alvo, {}, nil, ensaio: usar).iniciar
  end

  # Gatilhos que nascem fora do ouvinte (reunião, ADVBOX, ZapSign, documento). Erro do motor
  # nunca derruba quem chamou: o job do ADVBOX/ZapSign repetiria e duplicaria atividade, nota e sino.
  def self.externo(gatilho_tipo, alvo, dados = {})
    call(gatilho_tipo, alvo, dados)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: alvo.try(:account)).capture_exception
    Rails.logger.warn("[Ramon::Fluxos::Disparo] #{gatilho_tipo}: #{e.class}") # a mensagem pode ter dado do lead
    []
  end

  # Nos gatilhos DUAS_VEZES: com 'assumido' só os migrados (B5: do grupo que decidiu, quando o evento diz 'migracao' — vários
  # grupos dividem conversa_criada e mensagem_recebida); sem, só os demais. Em reuniao_marcada/cancelada o disparo com
  # 'assumido' vem antes dos efeitos do código (o ensaio vê o lead como estava).
  def self.da_vez?(fluxo, dados)
    return true if DUAS_VEZES.exclude?(fluxo.gatilho_tipo)
    return !dados.key?('assumido') unless Ramon::Fluxos::Migracao.migrado?(fluxo)

    dados.key?('assumido') && (dados['migracao'].nil? || Ramon::Fluxos::Migracao.gatilhos(dados['migracao']).key?(fluxo.sistema_chave))
  end

  def self.passa?(fluxo, dados, origem)
    return false if origem && (origem.fluxo_id == fluxo.id || origem.profundidade + 1 > PROFUNDIDADE_MAX)
    return false if fluxo.modo == 'normal' && fluxo.limite_atingido?

    filtro_ok?(Ramon::Fluxos::Grafo.new(fluxo.versao_publicada.grafo).gatilho['config'] || {}, dados)
  end

  def self.filtro_ok?(config, dados)
    regras = Array(config['regras'])
    return false unless regras.empty? || regras.include?(dados['regra'])

    { 'caixa_ids' => 'caixa_id', 'de_etapa_ids' => 'de_etapa_id', 'para_etapa_ids' => 'para_etapa_id' }.all? do |filtro, campo|
      lista = Array(config[filtro]).map(&:to_i)
      lista.empty? || lista.include?(dados[campo].to_i)
    end
  end

  def initialize(fluxo, alvo, dados, origem, ensaio: nil)
    @fluxo = fluxo
    @alvo = alvo
    @dados = dados
    @origem = origem
    @ensaio = ensaio
  end

  def iniciar
    return if @fluxo.origem == 'sistema' # D7: desenho só-leitura; quem roda é o código de hoje

    recomecar if RECOMECA.include?(@fluxo.gatilho_tipo) && @ensaio.nil?
    execucao = @fluxo.execucoes.create!(atributos)
    return Ramon::Fluxos::Executor.new(execucao).avancar! if @ensaio || na_hora?

    Ramon::FluxoAvancarJob.perform_later(execucao.id)
    execucao
  rescue ActiveRecord::RecordNotUnique
    nil # já existe execução viva desse fluxo nesse alvo
  end

  private

  def na_hora?
    (NA_HORA.include?(@fluxo.gatilho_tipo) || NA_HORA_CHAVES.include?(@fluxo.sistema_chave)) && Ramon::Fluxos::Migracao.migrado?(@fluxo)
  end

  # Fluxo migrado do código (B4+): quem decide se age é o evento ('assumido', lido 1 vez pelo código); os demais, o modo.
  def sombra? = Ramon::Fluxos::Migracao.migrado?(@fluxo) ? !@dados['assumido'] : @fluxo.modo == 'sombra'

  def lead_do_alvo = FluxoExecucao.lead_de(@alvo) # B5: só lead, tarefa, reunião e conversa têm lead

  # Sem isto, em modo normal o índice único barraria o ciclo novo e os lembretes seguiriam o horário antigo.
  # ponytail: só 'esperando' — uma execução 'rodando' (milissegundos entre passos) ainda barra a nova.
  def recomecar
    @fluxo.execucoes.where(alvo: @alvo, status: 'esperando').find_each do |velha|
      velha.with_lock do
        next unless velha.status == 'esperando' # o relógio pode ter acabado de reivindicar

        linha = { 'no' => 'cancelado', 'tipo' => 'cancelado', 'em' => Time.current.iso8601, 'saida' => nil,
                  'resumo' => 'cancelado: a reunião foi remarcada', 'erro' => false }
        velha.update!(status: 'cancelada', trilha: velha.trilha + [linha])
      end
    end
  end

  def atributos
    g = grafo.gatilho
    {
      account: @fluxo.account, versao: (@ensaio == 'rascunho' ? nil : @fluxo.versao_publicada), alvo: @alvo,
      ensaio: @ensaio.present? || sombra?, profundidade: @origem ? @origem.profundidade + 1 : 0,
      no_atual: grafo.proximo(g['id'], 's'), contexto: contexto, status: 'esperando', retomar_em: Time.current,
      trilha: [{ 'no' => g['id'], 'tipo' => 'gatilho', 'em' => Time.current.iso8601, 'saida' => 's',
                 'resumo' => g.dig('config', 'tipo'), 'erro' => false }]
    }
  end

  def grafo
    @grafo ||= Ramon::Fluxos::Grafo.new(@ensaio == 'rascunho' ? @fluxo.rascunho : @fluxo.versao_publicada.grafo)
  end

  def contexto
    base = { 'gatilho' => @dados, 'vars' => {}, 'etapa_inicial_id' => lead_do_alvo&.lead_stage_id }
    base['grafo'] = @fluxo.rascunho if @ensaio == 'rascunho'
    base['pular_esperas'] = true if @ensaio
    base.compact
  end
end
