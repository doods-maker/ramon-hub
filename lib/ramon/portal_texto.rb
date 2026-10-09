# lib/ramon/portal_texto.rb
# Tradução do ADVBOX para a língua do cliente (config/ramon/portal_etapas.yml).
# Calculado no render: mudar o YAML não exige re-sincronizar o espelho.
# PORTAL_TEXTOS_V2=on troca pelo dicionário v2 (portal_etapas_v2.yml: fases, linha do
# tempo, flag de e-mail) — desligado até o "aprovado" do Eduardo nos textos.
# ponytail: um módulo só pra toda a tradução do painel; separar a parte do tribunal se crescer mais.
module Ramon::PortalTexto # rubocop:disable Metrics/ModuleLength
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
    compilar = ->(regras) { Array(regras).map { |m| m.merge('re' => Regexp.new(m['regex'], Regexp::IGNORECASE)) } }
    dados.merge('marcos' => compilar.call(dados['marcos']), 'tribunal' => compilar.call(dados['tribunal'])).freeze
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

  ARQUIVADO = 'ARQUIVADO/ENCERRADO'.freeze
  CONCEDIDO = 'BENEFICIO CONCEDIDO / IMPLANTACAO'.freeze
  # Tarefa do ADVBOX com data (espelho 'agenda') → etapa do painel, por [tipo][processo na Justiça?].
  AGENDA = { 'audiencia' => { true => 'PAINEL AUDIENCIA MARCADA', false => 'PAINEL AUDIENCIA MARCADA' },
             'pericia' => { true => 'PAINEL PERICIA MARCADA', false => 'PERICIA AGENDADA' } }.freeze
  # Etapas sem notícia própria (só o nº CNJ ou o protocolo): mudar pra elas dentro da mesma fase não é novidade.
  SEM_NOTICIA = ['ACAO PROTOCOLADA', 'REQUERIMENTO PROTOCOLADO'].freeze

  # Encerrado = a equipe arquivou (grupo ARQUIVAMENTO) ou o tribunal deu baixa definitiva.
  def encerrado?(processo)
    normalizar(processo['fase']) == FASE_ENCERRADA || PortalCliente.etapa_cliente(processo) == ARQUIVADO
  end

  # Etapa que o cliente vê (v2): do tribunal e das tarefas, nunca da coluna "etapa" do ADVBOX, que a equipe
  # esquece de mover (Siemes/Ademir, 08/10). Exceções (a etapa vale): arquivado pela equipe mostra o motivo, e o
  # benefício concedido pelo INSS — pedido administrativo não tem andamento no ADVBOX (Eduardo, 08/10).
  def etapa_real(processo)
    return processo['etapa'] if normalizar(processo['fase']) == FASE_ENCERRADA || normalizar(processo['etapa']) == CONCEDIDO

    tribunal = etapa_do_tribunal(processo)
    agenda = Array(processo['agenda']).first
    return tribunal if tribunal == ARQUIVADO
    return AGENDA[agenda['tipo']][cnj?(processo)] if agenda

    tribunal || etapa_sem_andamento(processo)
  end

  # Baixa definitiva só encerra se nada andou depois: no eproc ela também marca a volta dos autos à origem.
  def etapa_do_tribunal(processo)
    achado = processo['tribunal']
    return if achado.nil? || (achado['etapa'] == ARQUIVADO && Array(processo['andamentos']).any? { |a| a['data'].to_s > achado['data'] })

    achado['etapa']
  end

  def etapa_sem_andamento(processo)
    return 'ACAO PROTOCOLADA' if cnj?(processo)
    return 'REQUERIMENTO PROTOCOLADO' if processo['protocolo'].present?

    'DOCUMENTOS SOLICITADOS - MKT' if Array(processo['docs_pendentes']).any?
  end

  # Andamento que define a fase → { 'etapa', 'data', 'titulo' }, em ordem cronológica: o mais recente vence (no
  # mesmo dia, a regra de cima), exceto que regra `sem_volta` (pagamento) não volta pra uma de baixo — sentença ou
  # acórdão depois do cumprimento não devolve o caso pra "O juiz decidiu". O achado do espelho anterior entra de
  # novo pelo título, então corrigir uma regra no YAML corrige também o que já estava gravado.
  def achado_do_tribunal(andamentos, anterior = nil)
    achados = (Array(andamentos) + [anterior].compact).filter_map { |a| achado(a['titulo'], a['data']) }
    escolhido = achados.sort_by { |t| [t['data'], -t['ordem']] }.reduce(nil) do |atual, t|
      atual && atual['sem_volta'] && t['ordem'] > atual['ordem'] ? atual : t
    end
    escolhido&.slice('etapa', 'data', 'titulo')
  end

  def achado(titulo, data)
    ordem = V2['tribunal'].index { |r| r['re'].match?(I18n.transliterate(titulo.to_s)) }
    return if ordem.nil?

    regra = V2['tribunal'][ordem]
    { 'etapa' => regra['etapa'], 'data' => data.to_s, 'titulo' => titulo, 'ordem' => ordem, 'sem_volta' => regra['sem_volta'] == true }
  end

  def cnj?(processo) = processo['numero'].to_s.gsub(/\D/, '').size == 20

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
    justica = cnj?(processo) || DEGRAUS_OPCIONAIS['justica'][1].include?(normalizar(processo['fase']))
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
    return %w[concluido Concluído] if encerrado?(processo)

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
    fases = V2['fases'].select { |f| degrau_visivel?(f['chave'], atual, processo) }
    posicao = fases.index { |f| f['chave'] == atual }
    fases.each_with_index.map { |f, i| f.slice('chave', 'nome', 'frase').merge('estado' => estado(i, posicao)) }
  end

  # Processo com nº CNJ passou pela Justiça mesmo que o degrau atual já seja outro (ex.: pagamento).
  def degrau_visivel?(chave, atual, processo)
    fases, steps = DEGRAUS_OPCIONAIS[chave]
    fases.nil? || fases.include?(atual) || steps.include?(normalizar(processo['fase'])) || (chave == 'justica' && cnj?(processo))
  end

  def estado(indice, posicao)
    return 'done' if indice < posicao
    return 'current' if indice == posicao

    'future'
  end
end
