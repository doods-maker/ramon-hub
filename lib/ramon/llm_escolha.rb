# Provedor e modelo POR FUNÇÃO (Inteligência → Uso e custo). Ponto único de leitura:
# a escolha mora em accounts.settings['captain_models'] (mecanismo do upstream: llm.yml +
# CaptainFeaturable + API captain/preferences); sem escolha válida, vale o env de antes.
#
# Termos de uso (decisão registrada): a assinatura do Claude (runner da VPS) NUNCA é o LLM
# do atendimento ao cliente nem do copiloto da equipe — só de tarefas internas acionadas
# pelo próprio gestor (hoje, o agente @claude). Trava aqui, na validação do Account e na tela.
module Ramon::LlmEscolha
  # função na tela → feature do llm.yml
  FEATURES = { 'atendimento' => 'assistant', 'copiloto' => 'copilot', 'documentos' => 'documentos' }.freeze
  ASSINATURA = 'claude_vps'.freeze
  FUNCOES_INTERNAS = %w[agente].freeze
  # funções internas (copiloto, colheita, ata, triagem): saíram da DeepSeek em 03/11, antes do App Review da Meta
  MODELO_INTERNO = 'claude-haiku-5-5'.freeze
  # chave de cada provedor = a mesma env que o Ramon::LlmClient usa
  CHAVES = { 'deepseek' => 'DEEPSEEK_API_KEY', 'openai' => 'OPENAI_API_KEY', 'anthropic' => 'ANTHROPIC_API_KEY',
             ASSINATURA => 'RAMON_AGENTE_TOKEN' }.freeze
  # DeepSeek desabilitada desde 03/11 (App Review da Meta): aparece na tela, mas não dá para escolher e
  # uma escolha salva cai na reserva. A chave segue no servidor; para religar, tirar daqui.
  DESABILITADOS = %w[deepseek].freeze

  module_function

  # { provider:, model: } da função — o que a conta escolheu ou, senão, a reserva do env.
  def para(account, funcao)
    escolhida(account, funcao.to_s) || reserva(funcao.to_s)
  end

  # 'tela' quando a escolha salva vale; 'reserva' quando cai no env.
  def fonte(account, funcao) = escolhida(account, funcao.to_s) ? 'tela' : 'reserva'

  def provedor_de(modelo) = Llm::Models.models.dig(modelo.to_s, 'provider')

  def assinatura?(modelo) = provedor_de(modelo) == ASSINATURA

  def chave?(provider) = DESABILITADOS.exclude?(provider.to_s) && ENV.fetch(CHAVES.fetch(provider.to_s, ''), nil).present?

  def chaves = CHAVES.keys.index_with { |provider| chave?(provider) }

  # Escolha salva que ainda vale: modelo da lista da feature, fora da assinatura (função
  # interna à parte) e com a chave do provedor no servidor — sem chave, cai na reserva.
  def escolhida(account, funcao)
    modelo = modelo_salvo(account, funcao)
    return if modelo.nil? || vetado?(modelo, funcao)

    par_de(modelo)
  end

  def modelo_salvo(account, funcao)
    feature = FEATURES[funcao]
    modelo = account&.captain_models&.dig(feature) if feature
    modelo if modelo.present? && Llm::Models.valid_model_for?(feature, modelo)
  end

  def vetado?(modelo, funcao)
    provider = provedor_de(modelo)
    (provider == ASSINATURA && FUNCOES_INTERNAS.exclude?(funcao)) || !chave?(provider)
  end

  # Sem escolha válida na tela: o env de cada caminho e, no copiloto, o modelo interno.
  def reserva(funcao)
    case funcao
    when 'atendimento' then par_de(ENV.fetch('RAMON_CAPTAIN_MODEL', nil).presence || modelo_captain || LlmConstants::DEFAULT_MODEL)
    when 'documentos' then par_de(modelo_captain || Llm::Config::DEFAULT_MODEL)
    when 'agente' then { provider: ASSINATURA, model: 'claude-vps' }
    else par_de(modelo_copiloto)
    end
  end

  def par_de(modelo) = { provider: provedor_de(modelo), model: modelo }

  def modelo_copiloto = ENV.fetch('RAMON_COPILOT_MODEL', nil).presence || MODELO_INTERNO

  def modelo_captain = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence
end
