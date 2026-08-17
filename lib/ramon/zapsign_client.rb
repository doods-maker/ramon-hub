# Cliente HTTP da API do ZapSign (assinatura eletrônica).
# Doc: https://docs.zapsign.com.br — Bearer token, criar doc via modelo em
# POST /api/v1/models/create-doc/. O modelo da banca já dispara contrato +
# procuração juntos (extra_templates) e o signatário herda nome/email/telefone
# das variáveis.
class Ramon::ZapsignClient
  class UnavailableError < StandardError; end

  class RequestError < StandardError
    attr_reader :code, :body

    def initialize(code, body)
      @code = code
      @body = body
      super("ZapSign respondeu HTTP #{code}")
    end
  end

  BASE = 'https://api.zapsign.com.br/api/v1'.freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30
  TEMPLATES_CACHE = 10.minutes

  # Modelos ativos da conta (GET /templates/, 20 por página). Cache curto: a lista
  # muda só quando alguém cadastra modelo no ZapSign.
  def self.templates
    token = ENV.fetch('ZAPSIGN_API_TOKEN', nil)
    raise UnavailableError, 'ZapSign indisponível: ZAPSIGN_API_TOKEN não configurado' if token.blank?

    Rails.cache.fetch('ramon/zapsign/templates', expires_in: TEMPLATES_CACHE) do
      page = 1
      itens = []
      loop do
        body = get_json("#{BASE}/templates/", token, page)
        itens.concat(Array(body['results']))
        break if body['next'].blank? || page >= 10

        page += 1
      end
      itens.select { |t| t['active'] }.map { |t| t.slice('token', 'name') }
    end
  end

  def self.get_json(url, token, page)
    response = HTTParty.get(url, query: { page: page },
                                 headers: { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' },
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    return response.parsed_response if response.success?
    raise UnavailableError, "ZapSign respondeu HTTP #{response.code}" if response.code >= 500

    raise RequestError.new(response.code, response.parsed_response)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, Errno::ETIMEDOUT,
         SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError => e
    raise UnavailableError, "ZapSign indisponível: #{e.message}"
  end
  private_class_method :get_json

  def self.create_doc_from_template(body)
    token = ENV.fetch('ZAPSIGN_API_TOKEN', nil)
    raise UnavailableError, 'ZapSign indisponível: ZAPSIGN_API_TOKEN não configurado' if token.blank?

    response = HTTParty.post("#{BASE}/models/create-doc/",
                             body: body.to_json,
                             headers: { 'Authorization' => "Bearer #{token}",
                                        'Content-Type' => 'application/json',
                                        'Accept' => 'application/json' },
                             open_timeout: OPEN_TIMEOUT,
                             read_timeout: READ_TIMEOUT)
    return response.parsed_response if response.success?
    raise UnavailableError, "ZapSign respondeu HTTP #{response.code}" if response.code >= 500

    raise RequestError.new(response.code, response.parsed_response)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, Errno::ETIMEDOUT,
         SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError => e
    raise UnavailableError, "ZapSign indisponível: #{e.message}"
  end
end
