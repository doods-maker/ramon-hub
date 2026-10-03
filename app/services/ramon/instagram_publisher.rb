# Publica uma peça (carrossel/estático) no feed do @ramonantonioadvogados pela Graph API
# do Instagram — paridade com motor-marketing/lib/publicar-ig.mjs, SEM stories (decisão
# do Eduardo 02/10: arte 4:5 quebra no story). Colaborador: crédito na legenda → @.
class Ramon::InstagramPublisher
  GRAPH = 'https://graph.instagram.com/v26.0'.freeze
  PRAZO = 300 # s, relógio de parede, pro contêiner ficar pronto
  ABRIR = 10 # s
  LER = 30 # s

  # Espelho de motor-marketing packs/marca-ramon-antonio/brand.json → identidades (22/09).
  COLABORADORES = {
    'Dr. Ramon Antonio' => 'ramon_antonio__', 'Eduardo Schlata' => 'eduardoschlata', 'Brenda Antunes' => 'brendantunes',
    'Rafaela Pinter' => 'rafaelabpf', 'Tamires de Farias' => 'tamidefarias', 'Crisleine Antonio' => 'crisleine_antonio'
  }.freeze

  class Erro < StandardError; end

  def initialize(peca, token: GlobalConfigService.load('RAMON_IG_PUBLISH_TOKEN', nil), espera: 5)
    @peca = peca
    @token = token
    @espera = espera
  end

  def publicar
    raise Erro, 'Token do Instagram ausente (super admin → Instagram → RAMON_IG_PUBLISH_TOKEN)' if @token.blank?

    container = @peca.tipo == 'carrossel' ? carrossel : post('me/media', base.merge(image_url: @peca.imagens.first))['id']
    aguardar(container)
    publicar_container(container)
  end

  def permalink(media_id)
    get(media_id, fields: 'permalink')['permalink']
  rescue StandardError
    nil
  end

  private

  # Falha AQUI é ambígua: a Meta pode ter publicado e só perdemos a resposta.
  def publicar_container(container)
    id = post('me/media_publish', creation_id: container)['id']
    raise Erro, 'resposta sem id' if id.blank?

    id
  rescue StandardError => e
    raise Erro, "Pode ter ido ao ar — conferir no Instagram antes de tentar de novo. (#{e.message})"
  end

  def carrossel
    filhos = @peca.imagens.map { |url| post('me/media', image_url: url, is_carousel_item: true)['id'] }
    post('me/media', base.merge(media_type: 'CAROUSEL', children: filhos.join(',')))['id']
  end

  def base
    achados = COLABORADORES.select { |nome, _| @peca.legenda.to_s.include?(nome) }.values.first(3)
    { caption: @peca.legenda }.merge(achados.any? ? { collaborators: achados.to_json } : {})
  end

  def aguardar(id)
    limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PRAZO
    loop do
      codigo = get(id, fields: 'status_code')['status_code']
      return if codigo == 'FINISHED'
      raise Erro, "Contêiner #{id}: #{codigo}" if %w[ERROR EXPIRED].include?(codigo)
      raise Erro, "Contêiner #{id} não ficou pronto a tempo" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limite

      sleep @espera
    end
  end

  def post(caminho, params)
    uri = URI("#{GRAPH}/#{caminho}")
    req = Net::HTTP::Post.new(uri)
    req.set_form_data(params.merge(access_token: @token))
    enviar(uri, req)
  end

  def get(caminho, params)
    uri = URI("#{GRAPH}/#{caminho}")
    uri.query = URI.encode_www_form(params.merge(access_token: @token))
    enviar(uri, Net::HTTP::Get.new(uri))
  end

  # Prazo explícito: sem ele um travamento de rede deixa a peça "publicando" sem saber se foi ao ar.
  def enviar(uri, req)
    responder Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: ABRIR, read_timeout: LER) { |http| http.request(req) }
  end

  def responder(res)
    corpo = corpo_json(res)
    unless res.is_a?(Net::HTTPSuccess)
      mensagem = corpo.is_a?(Hash) && corpo['error'].is_a?(Hash) ? corpo['error']['message'] : nil
      raise Erro, mensagem.presence || "HTTP #{res.code}"
    end
    raise Erro, 'Resposta inválida da Meta' unless corpo.is_a?(Hash)

    corpo
  end

  def corpo_json(res)
    JSON.parse(res.body.presence || '{}')
  rescue JSON::ParserError
    nil
  end
end
