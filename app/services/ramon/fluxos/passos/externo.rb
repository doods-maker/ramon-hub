# Passos que falam com sistemas de fora (spec §4.3):
# - advbox: tarefa ou movimentação FIXA no processo do lead, com IDs escolhidos na tela
#   (advbox_configuracoes) — escrita determinística pelo mesmo caminho do MCP, não é a IA decidindo.
# - webhook: POST JSON do contexto; só como último passo (Grafo#erros_webhook); SafeFetch barra
#   rede interna; nunca leva token/env/config do hub.
module Ramon::Fluxos::Passos::Externo
  FERRAMENTA = { 'tarefa' => 'advbox_criar_tarefa', 'movimentacao' => 'advbox_criar_movimentacao' }.freeze
  ABRIR = 2 # segundos
  LER = 5
  # decisão do Eduardo: nome e telefone, sem CPF/documentos — campos livres do lead (que podem ter CPF) nunca saem
  CAMPOS_WEBHOOK = %w[nome nome_completo telefone etapa tese origem canal valor prioridade responsavel].freeze
  IMPOSSIVEL = Ramon::Fluxos::PassoImpossivel

  module_function

  def advbox(config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    processo = lead.custom_attributes&.dig('advbox', 'lawsuits_id')
    raise IMPOSSIVEL, 'o lead ainda não tem processo no ADVBOX' if processo.blank?
    return { saida: 's', resumo: "faria: #{config['acao']} no ADVBOX (processo #{processo})" } if ctx.ensaio?

    chamar_advbox(config, processo, ctx)
    { saida: 's', resumo: "ADVBOX: #{config['acao']} no processo #{processo}" }
  end

  # erro de configuração (acao/IDs faltando, token ausente) não se resolve repetindo
  def chamar_advbox(config, processo, ctx)
    ferramenta = FERRAMENTA[config['acao']] || raise(IMPOSSIVEL, 'passo ADVBOX sem ação válida (tarefa ou movimentação)')
    Ramon::AdvboxMcpService::FETCHERS.fetch(ferramenta).call(argumentos(config, processo, ctx))
  rescue KeyError
    raise IMPOSSIVEL, 'passo ADVBOX incompleto: escolha o tipo de tarefa e o responsável'
  rescue Ramon::AdvboxClient::RequestError => e
    raise IMPOSSIVEL, "ADVBOX recusou (HTTP #{e.code})"
  rescue Ramon::AdvboxClient::UnavailableError => e
    raise IMPOSSIVEL, 'ADVBOX não configurado no hub (token ausente)' if e.message.include?('não configurado')

    raise
  end

  def argumentos(config, processo, ctx)
    base = { 'processo_id' => processo, 'descricao' => ctx.interpolar(config['descricao']) }
    return base if config['acao'] == 'movimentacao'

    prazo = (Time.find_zone!(Fluxo::ZONA).today + config['prazo_dias'].to_i).iso8601 if config['prazo_dias'].present?
    base.merge('tipo_tarefa_id' => config['tipo_tarefa_id'], 'responsavel_id' => config['responsavel_id'], 'prazo' => prazo)
  end

  def webhook(config, ctx)
    url = config['url'].to_s
    return { saida: 's', resumo: "faria: POST para #{host(url)}" } if ctx.ensaio?

    SafeFetch.fetch(url, method: :post, body: payload(ctx).to_json, headers: { 'Content-Type' => 'application/json' },
                         open_timeout: ABRIR, read_timeout: LER, validate_content_type: false) { |_resposta| nil }
    { saida: 's', resumo: "webhook: POST para #{host(url)}" }
  rescue SafeFetch::InvalidUrlError, SafeFetch::UnsafeUrlError => e
    raise IMPOSSIVEL, "endereço do webhook recusado (#{e.message.truncate(80)})"
  rescue SafeFetch::HttpError => e
    status = e.message[/\A\d{3}/].to_i # HttpError só traz "404 Not Found" na mensagem
    raise IMPOSSIVEL, "webhook recusado por #{host(url)} (HTTP #{status})" if status.between?(400, 499) && [408, 429].exclude?(status)

    raise
  end

  # Só o caso — nada de token, env ou config do hub. `dados` só leva CAMPOS_WEBHOOK.
  def payload(ctx)
    execucao = ctx.execucao
    { fluxo: execucao.fluxo.nome, fluxo_id: execucao.fluxo_id, execucao_id: execucao.id, alvo_tipo: execucao.alvo_type,
      alvo_id: execucao.alvo_id, lead_id: ctx.lead&.id, enviado_em: Time.current.iso8601, dados: ctx.dados.slice(*CAMPOS_WEBHOOK) }
  end

  # a URL pode carregar token (ex.: hooks do Make/Zapier): na trilha só o host
  def host(url) = url[%r{\Ahttps?://([^/?#]+)}, 1] || '?'
end
