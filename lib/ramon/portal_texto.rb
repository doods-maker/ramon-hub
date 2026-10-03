# lib/ramon/portal_texto.rb
# Tradução do ADVBOX para a língua do cliente (config/ramon/portal_etapas.yml).
# Calculado no render: mudar o YAML não exige re-sincronizar o espelho.
# PORTAL_TEXTOS_V2=on troca pelo dicionário v2 (portal_etapas_v2.yml: fases, linha do
# tempo, flag de e-mail) — desligado até o "aprovado" do Eduardo nos textos.
module Ramon::PortalTexto
  FASE_ENCERRADA = 'ARQUIVAMENTO'.freeze
  PADRAO_V1 = { 'titulo' => 'Em andamento', 'o_que_esperar' => 'Nossa equipe está cuidando do seu caso.' }.freeze
  # Degrau opcional da linha do tempo → [fases atuais que o revelam, steps do ADVBOX que o revelam].
  # Pagamento só aparece quando o caso ESTÁ nele: como degrau futuro prometeria ganho (Eduardo, 03/10).
  DEGRAUS_OPCIONAIS = {
    'justica' => [%w[justica recurso], %w[JUDICIAL RECURSAL EXECUCAO/COBRANCA]],
    'recurso' => [%w[recurso], %w[RECURSAL]],
    'pagamento' => [%w[pagamento], []]
  }.freeze

  def self.carregar(arquivo)
    dados = YAML.load_file(Rails.root.join('config/ramon', arquivo))
    dados.merge('marcos' => dados['marcos'].map { |m| m.merge('re' => Regexp.new(m['regex'], Regexp::IGNORECASE)) }).freeze
  end

  V1 = carregar('portal_etapas.yml')
  V2 = carregar('portal_etapas_v2.yml')

  module_function

  # Lido a cada chamada (não no boot) pra spec poder ligar a chave com with_modified_env.
  def v2? = ENV['PORTAL_TEXTOS_V2'] == 'on'

  def dados = v2? ? V2 : V1

  def normalizar(str)
    I18n.transliterate(str.to_s).upcase.squish
  end

  def etapa(stage)
    return etapa_v2(stage) if v2?
    return PADRAO_V1 if stage.blank?

    V1['etapas'][normalizar(stage)] || { 'titulo' => stage.to_s.downcase.capitalize,
                                         'o_que_esperar' => 'Nossa equipe está cuidando desta etapa. Avisamos você a cada avanço.' }
  end

  # v2: etapa vazia, interna ou fora do dicionário nunca mostra o nome cru do ADVBOX.
  def etapa_v2(stage)
    texto = V2['etapas'][normalizar(stage)]
    texto && texto['interna'] != true ? texto : V2['padrao']
  end

  # andamentos: [{ 'data' => 'YYYY-MM-DD', 'titulo' => }] em qualquer ordem.
  def marcos(andamentos)
    por_tipo = {}
    Array(andamentos).sort_by { |a| a['data'].to_s }.each do |a|
      texto = I18n.transliterate(a['titulo'].to_s)
      marco = dados['marcos'].find { |m| m['re'].match?(texto) }
      next unless marco

      por_tipo[marco['tipo']] = { 'data' => a['data'], 'tipo' => marco['tipo'], 'titulo' => marco['titulo'],
                                  'explicacao' => marco['explicacao'], 'delicada' => marco['delicada'] == true }
    end
    por_tipo.values.sort_by { |m| m['data'].to_s }
  end

  def interna?(stage)
    dados['etapas'].dig(normalizar(stage), 'interna') == true
  end

  # v1 não tem a flag: toda mudança de etapa não delicada vai por e-mail.
  def email?(stage)
    dados['etapas'].dig(normalizar(stage), 'email') != false
  end

  def encerrado?(step)
    normalizar(step) == FASE_ENCERRADA
  end

  # Tipo do ADVBOX que só diz o procedimento, não o assunto: o painel não inventa título.
  TIPOS_SEM_ASSUNTO = ['PROCEDIMENTO DO JUIZADO ESPECIAL CIVEL', 'CUMPRIMENTO DE SENTENCA CONTRA FAZENDA PUBLICA',
                       'PROCEDIMENTO COMUM', 'PROCEDIMENTO COMUM CIVEL', 'TAREFAS ADMINISTRATIVAS'].freeze
  SIGLAS = /\b(inss|pcd|irpf|rpv|fgts|ctps|dpvat)\b/

  # "AUXÍLIO-ACIDENTE - COMUM (B36)" → "Auxílio-acidente"; tipo só de procedimento → nil.
  def assunto(tipo)
    base = tipo.to_s.sub(/\s*\(.*\)\s*\z/, '').split(' - ').first.to_s.strip
    return if base.empty? || TIPOS_SEM_ASSUNTO.include?(normalizar(base))

    base.downcase.capitalize.gsub(SIGLAS, &:upcase)
  end

  # Nº com 20 dígitos = padrão CNJ; sem número, o grupo do ADVBOX decide.
  def onde(processo)
    justica = processo['numero'].to_s.gsub(/\D/, '').size == 20 || DEGRAUS_OPCIONAIS['justica'][1].include?(normalizar(processo['fase']))
    justica ? 'Processo na Justiça' : 'Pedido no INSS'
  end

  # Etapas que a EQUIPE marca como positivas no ADVBOX → selo verde. Resultado ainda em análise
  # (etapa `delicada`) fica em cinza: o painel nunca antecipa resultado (regra do Eduardo, 03/10).
  ETAPAS_POSITIVAS = {
    'BENEFICIO CONCEDIDO / IMPLANTACAO' => 'Aprovado',
    'RPV / PRECATORIO EMITIDO' => 'Pagamento a caminho',
    'PAGAMENTO RECEBIDO / PAGAR CLIENTE' => 'Valor liberado',
    'PRESTAR CONTAS E PAGAR AO CLIENTE' => 'Valor liberado',
    'PAGAMENTO REALIZADO' => 'Pago'
  }.freeze

  # [tom, rótulo] do selo: aprovado (verde) · analise/concluido (pedra) · andamento (ouro).
  def status(processo)
    return %w[concluido Concluído] if encerrado?(processo['fase'])

    stage = normalizar(PortalCliente.etapa_cliente(processo))
    return ['aprovado', ETAPAS_POSITIVAS[stage]] if ETAPAS_POSITIVAS.key?(stage)
    return ['analise', 'Em análise'] if dados['etapas'].dig(stage, 'delicada')

    ['andamento', 'Em andamento']
  end

  # [título, linha de baixo] que diferenciam um processo do outro pro cliente.
  def identificacao(processo)
    numero = processo['numero'].presence && "nº #{processo['numero']}"
    titulo = assunto(processo['tipo'])
    titulo ? [titulo, [onde(processo), numero].compact.join(' · ')] : [onde(processo), numero]
  end

  # Fase (chave de V2['fases']) da etapa; etapa interna/desconhecida cai no grupo (step) do ADVBOX.
  def fase_de(stage, step)
    V2['etapas'].dig(normalizar(stage), 'fase') || V2['grupo_fase'][normalizar(step)]
  end

  # Degraus [{ 'chave', 'nome', 'frase', 'estado' => done|current|future }] da tela do processo (só v2).
  # ponytail: sem histórico de etapas no espelho, "passou por Justiça/Recurso" é inferido do
  # grupo atual — processo judicial que já está em ARQUIVAMENTO ou RH/FINANCEIRO perde o degrau.
  # Guardar as fases vistas no espelho (PortalNovidades) resolve, se incomodar.
  def linha_do_tempo(processo)
    atual = fase_de(PortalCliente.etapa_cliente(processo), processo['fase']) || 'documentos'
    fases = V2['fases'].select { |f| degrau_visivel?(f['chave'], atual, processo['fase']) }
    posicao = fases.index { |f| f['chave'] == atual }
    fases.each_with_index.map { |f, i| f.slice('chave', 'nome', 'frase').merge('estado' => estado(i, posicao)) }
  end

  def degrau_visivel?(chave, atual, step)
    fases, steps = DEGRAUS_OPCIONAIS[chave]
    fases.nil? || fases.include?(atual) || steps.include?(normalizar(step))
  end

  def estado(indice, posicao)
    return 'done' if indice < posicao
    return 'current' if indice == posicao

    'future'
  end
end
