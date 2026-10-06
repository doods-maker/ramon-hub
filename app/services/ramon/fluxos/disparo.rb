# Transforma um evento (ou um clique) em execuções de fluxo (spec §6): acha os fluxos
# ativos com aquele gatilho, aplica o filtro, o limite do dia e a profundidade de cadeia,
# e cria a execução — o índice único parcial barra 2 execuções vivas no mesmo alvo.
# Toda execução nasce 'esperando' e vencida: o Executor a reivindica (ensaio: na hora).
class Ramon::Fluxos::Disparo
  PROFUNDIDADE_MAX = 3

  def self.call(gatilho_tipo, alvo, dados = {}, origem: nil)
    account = alvo.account
    account.fluxos.executaveis.where(gatilho_tipo: gatilho_tipo).includes(:versao_publicada).filter_map do |fluxo|
      new(fluxo, alvo, dados, origem).iniciar if passa?(fluxo, dados, origem)
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
    execucao = @fluxo.execucoes.create!(atributos)
    return Ramon::Fluxos::Executor.new(execucao).avancar! if @ensaio

    Ramon::FluxoAvancarJob.perform_later(execucao.id)
    execucao
  rescue ActiveRecord::RecordNotUnique
    nil # já existe execução viva desse fluxo nesse alvo
  end

  private

  def atributos
    g = grafo.gatilho
    {
      account: @fluxo.account, versao: (@ensaio == 'rascunho' ? nil : @fluxo.versao_publicada), alvo: @alvo,
      ensaio: @ensaio.present? || @fluxo.modo == 'sombra', profundidade: @origem ? @origem.profundidade + 1 : 0,
      no_atual: grafo.proximo(g['id'], 's'), contexto: contexto, status: 'esperando', retomar_em: Time.current,
      trilha: [{ 'no' => g['id'], 'tipo' => 'gatilho', 'em' => Time.current.iso8601, 'saida' => 's',
                 'resumo' => g.dig('config', 'tipo'), 'erro' => false }]
    }
  end

  def grafo
    @grafo ||= Ramon::Fluxos::Grafo.new(@ensaio == 'rascunho' ? @fluxo.rascunho : @fluxo.versao_publicada.grafo)
  end

  def contexto
    lead = @alvo.is_a?(Lead) ? @alvo : @fluxo.account.leads.where(conversation_id: @alvo.id).reorder(id: :desc).first
    base = { 'gatilho' => @dados, 'vars' => {}, 'etapa_inicial_id' => lead&.lead_stage_id }
    base['grafo'] = @fluxo.rascunho if @ensaio == 'rascunho'
    base['pular_esperas'] = true if @ensaio
    base.compact
  end
end
