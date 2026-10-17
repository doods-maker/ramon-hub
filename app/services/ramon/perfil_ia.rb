# Perfil da IA (spec 2026-10-17 "Como a IA atende", ADR 0009): até onde a IA vai sozinha (Marcador na Trilha das
# Etapas abertas do Funil), a Permissão de cada ação e os Gatilhos de equipe. Dono único de
# account.settings['ia_atendimento'] = { 'padrao' => cfg, 'teses' => { id => cfg }, 'caixas' => { id => cfg } }.
# Quem manda: Pausa da conversa → tese do lead (a própria ou o padrão) → caixa (só sem tese) → padrão.
class Ramon::PerfilIa
  CHAVE = 'ia_atendimento'.freeze
  ACOES = %w[fora_do_horario pedir_documentos desqualificar mover_etapa marcar_reuniao citar_honorario logistica
             contrato_zapsign].freeze
  # Sem "nunca": fora do horário exigiria resposta adiada; logística não tem Tool para desligar.
  SEM_NUNCA = %w[fora_do_horario logistica].freeze
  INICIO = '_inicio'.freeze
  FIM = '_fim'.freeze
  PAUSAS = %w[pausada rascunho].freeze
  PAUSA = 'ia_pausa'.freeze
  # ponytail: só as chaves, em ordem; os textos para o prompt entram com a montagem dos gatilhos (Task 7)
  GATILHOS = %w[pediu_pessoa juridica outra_area fora_do_tema honorario_de_novo nao_le irritado tem_advogado desconto
                clausula].freeze
  PERMISSOES = { 's' => :sozinha, 'r' => :rascunho, 'n' => :nunca }.freeze

  PRONTOS = {
    'cautelosa' => {
      'marcador' => 'fase-qualificacao', 'gatilhos' => GATILHOS,
      'permissoes' => { 'fora_do_horario' => 'r', 'pedir_documentos' => 's', 'desqualificar' => 'r', 'mover_etapa' => 'r',
                        'marcar_reuniao' => 'r', 'citar_honorario' => 'n', 'logistica' => 'r', 'contrato_zapsign' => 'n' }
    },
    'equilibrada' => {
      'marcador' => 'fase-reuniao-agendada', 'gatilhos' => (GATILHOS - %w[nao_le]).freeze,
      'permissoes' => { 'fora_do_horario' => 's', 'pedir_documentos' => 's', 'desqualificar' => 'r', 'mover_etapa' => 's',
                        'marcar_reuniao' => 's', 'citar_honorario' => 'r', 'logistica' => 's', 'contrato_zapsign' => 'r' }
    },
    'acelerada' => {
      'marcador' => FIM, 'gatilhos' => %w[pediu_pessoa juridica outra_area fora_do_tema desconto clausula].freeze,
      'permissoes' => ACOES.index_with('s')
    }
  }.freeze

  # Padrão do escritório enquanto nada foi salvo = o piloto_limitado de hoje (spec, Migração).
  INICIAL = { 'base' => 'cautelosa', 'marcador' => INICIO,
              'permissoes' => { 'logistica' => 's', 'fora_do_horario' => 's', 'citar_honorario' => 'r',
                                'contrato_zapsign' => 'r' } }.freeze

  # "Nunca" = a Tool nem é oferecida ao modelo no turno.
  TOOLS_DA_ACAO = { 'pedir_documentos' => %w[solicitar_documento enviar_link_portal], 'citar_honorario' => %w[simular_honorario],
                    'marcar_reuniao' => %w[horarios_livres agendar_reuniao],
                    'contrato_zapsign' => %w[preparar_contrato_zapsign] }.freeze
  # Tools cujo resultado vai no texto da resposta: em rascunho, seguram a resposta inteira.
  ACAO_DA_TOOL_DE_TEXTO = { 'simular_honorario' => 'citar_honorario', 'solicitar_documento' => 'pedir_documentos',
                            'enviar_link_portal' => 'pedir_documentos',
                            'preparar_contrato_zapsign' => 'contrato_zapsign' }.freeze

  attr_reader :conversa, :lead, :etapa, :pausa, :cfg, :alvo, :origem

  # registro = Conversation ou Lead. Testar: lead descartável sem conversa com o cfg da tela (perfil_ia_simulado).
  def self.de(registro)
    lead = registro.is_a?(Lead) ? registro : registro.account.leads.find_by(conversation_id: registro.id)
    conversa = registro.is_a?(Lead) ? registro.conversation : registro
    alvo, cfg = alvo_e_cfg(registro.account, lead, conversa)
    simulado = lead&.perfil_ia_simulado if conversa.nil?
    return new(conversa, lead, alvo, normalizar(simulado), :teste) if simulado.is_a?(Hash)

    new(conversa, lead, alvo, cfg, alvo.split(':').first.to_sym)
  end

  # cfg gravado de um alvo, já normalizado; nil = não tem (tese/caixa seguem o padrão).
  def self.cfg_salvo(account, tipo, id = nil)
    bruto = [CHAVE, tipo, id&.to_s].compact.reduce(account.settings) { |nivel, chave| nivel[chave] if nivel.is_a?(Hash) }
    normalizar(bruto) if bruto.is_a?(Hash)
  end

  # O label da Etapa: estável a renomeação.
  def self.chave_da_etapa(lead_stage) = lead_stage ? lead_stage.label.to_s : ''

  # Tese manda (a própria ou o padrão); a caixa só vale para lead sem tese.
  def self.alvo_e_cfg(account, lead, conversa)
    tipo, id, prefixo = lead&.thesis_id ? ['teses', lead.thesis_id, 'tese'] : ['caixas', conversa&.inbox_id, 'caixa']
    cfg = id && cfg_salvo(account, tipo, id)
    cfg ? ["#{prefixo}:#{id}", cfg] : ['padrao', cfg_salvo(account, 'padrao') || INICIAL]
  end

  # Descarta chave e valor fora da lista: o que sobra vem da base.
  def self.normalizar(cfg)
    { 'base' => cfg['base'].presence_in(PRONTOS.keys),
      'marcador' => (cfg['marcador'] if cfg['marcador'].is_a?(String)),
      'permissoes' => permissoes_validas(cfg['permissoes']),
      'gatilhos' => gatilhos_validos(cfg['gatilhos']) }.compact
  end

  def self.permissoes_validas(permissoes)
    return {} unless permissoes.is_a?(Hash)

    permissoes.slice(*ACOES).select { |acao, valor| PERMISSOES.key?(valor) && !(valor == 'n' && SEM_NUNCA.include?(acao)) }
  end

  def self.gatilhos_validos(gatilhos)
    return {} unless gatilhos.is_a?(Hash)

    gatilhos.select { |_, lista| lista.is_a?(Array) }.transform_values { |lista| GATILHOS & lista }
  end
  private_class_method :alvo_e_cfg, :normalizar, :permissoes_validas, :gatilhos_validos

  def initialize(conversa, lead, alvo, cfg, origem)
    @conversa = conversa
    @lead = lead
    @alvo = alvo
    @cfg = cfg
    @origem = origem
    @account = (lead || conversa).account
    @etapa = lead&.lead_stage
    @pausa = conversa&.custom_attributes&.[](PAUSA).presence_in(PAUSAS)
  end

  def base = @cfg['base'] || 'cautelosa'

  # Label de uma Etapa aberta, _inicio ou _fim; label que não está na Trilha (etapa apagada) = _inicio.
  def marcador
    valor = @cfg['marcador'] || pronto['marcador']
    [INICIO, FIM, *abertas.map(&:label)].include?(valor) ? valor : INICIO
  end

  def permissao(acao)
    return :nunca if acao.to_s == 'desconto' # regra do escritório, linha travada

    PERMISSOES.fetch(@cfg.dig('permissoes', acao.to_s) || pronto['permissoes'].fetch(acao.to_s))
  end

  def estado(etapa = @etapa)
    return :pausada if @pausa == 'pausada' || etapa&.is_lost
    return :fechado if etapa&.is_won # pós-venda é das pessoas: só rascunho

    posicao(etapa) <= indice_do_marcador ? :sozinha : :rascunho
  end

  def tools_bloqueadas = TOOLS_DA_ACAO.filter_map { |acao, tools| tools if permissao(acao) == :nunca }.flatten

  def gatilhos(etapa = @etapa) = @cfg.dig('gatilhos', self.class.chave_da_etapa(etapa || abertas.first)) || pronto['gatilhos']

  def direto?(acao) = @pausa.nil? && permissao(acao) == :sozinha && estado == :sozinha

  # Antes do Marcador sai sozinha; depois, só com logística = sozinha.
  def logistica_sai?(etapa = @etapa)
    agora = estado(etapa)
    @pausa.nil? && %i[fechado pausada].exclude?(agora) && (agora == :sozinha || permissao('logistica') == :sozinha)
  end

  def nome = personalizado? ? 'Personalizado' : base.capitalize

  private

  def pronto = PRONTOS[base]

  # Etapas abertas da conta na ordem do Funil (default_scope por position).
  def abertas
    @abertas ||= @account.lead_stages.where(is_won: false, is_lost: false).to_a
  end

  def indice_do_marcador
    case marcador
    when INICIO then -1
    when FIM then abertas.size - 1
    else abertas.index { |e| e.label == marcador }
    end
  end

  # Sem etapa = a 1ª aberta; etapa fora da Trilha (não deveria) = depois de todas, rascunho.
  def posicao(etapa) = etapa ? (abertas.index { |e| e.id == etapa.id } || abertas.size) : 0

  # Compara o valor efetivo (o que a IA faria), não o gravado.
  def personalizado?
    marcador != pronto['marcador'] ||
      ACOES.any? { |acao| permissao(acao) != PERMISSOES.fetch(pronto['permissoes'][acao]) } ||
      abertas.any? { |e| gatilhos(e) != pronto['gatilhos'] }
  end
end
