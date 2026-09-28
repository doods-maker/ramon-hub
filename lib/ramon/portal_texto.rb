# lib/ramon/portal_texto.rb
# Tradução do ADVBOX para a língua do cliente (config/ramon/portal_etapas.yml).
# Calculado no render: mudar o YAML não exige re-sincronizar o espelho.
# PORTAL_TEXTOS_V2=on troca pelo dicionário v2 (portal_etapas_v2.yml: fases, linha do
# tempo, flag de e-mail) — desligado até o "aprovado" do Eduardo nos textos.
module Ramon::PortalTexto
  FASE_ENCERRADA = 'ARQUIVAMENTO'.freeze
  PADRAO_V1 = { 'titulo' => 'Em andamento', 'o_que_esperar' => 'Nossa equipe está cuidando do seu caso.' }.freeze
  # Degrau opcional da linha do tempo → [fases atuais que o revelam, steps do ADVBOX que o revelam].
  DEGRAUS_OPCIONAIS = {
    'justica' => [%w[justica recurso], %w[JUDICIAL RECURSAL EXECUCAO/COBRANCA]],
    'recurso' => [%w[recurso], %w[RECURSAL]]
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

  # Fase (chave de V2['fases']) da etapa; etapa interna/desconhecida cai no grupo (step) do ADVBOX.
  def fase_de(stage, step)
    V2['etapas'].dig(normalizar(stage), 'fase') || V2['grupo_fase'][normalizar(step)]
  end

  # Degraus [{ 'nome', 'frase', 'estado' => done|current|future }] da tela do processo (só v2).
  # ponytail: sem histórico de etapas no espelho, "passou por Justiça/Recurso" é inferido do
  # grupo atual — processo judicial que já está em ARQUIVAMENTO ou RH/FINANCEIRO perde o degrau.
  # Guardar as fases vistas no espelho (PortalNovidades) resolve, se incomodar.
  def linha_do_tempo(processo)
    atual = fase_de(PortalCliente.etapa_cliente(processo), processo['fase']) || 'documentos'
    fases = V2['fases'].select { |f| degrau_visivel?(f['chave'], atual, processo['fase']) }
    posicao = fases.index { |f| f['chave'] == atual }
    fases.each_with_index.map { |f, i| { 'nome' => f['nome'], 'frase' => f['frase'], 'estado' => estado(i, posicao) } }
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
