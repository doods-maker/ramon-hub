# Cliente HTTP da API do AdvBox (gestão processual da banca).
# Doc: https://api.softwareadvbox.com.br/docs — Bearer token, base /api/v1.
# Calibrado contra a API real 13/07/2026: busca parcial por nome do cliente em
# /lawsuits?name=, andamentos em /movements/{lawsuit_id} e publicações em
# /publications/{lawsuit_id}. O Cloudflare deles bloqueia requisição sem
# User-Agent — sempre mandar um. Filtros são combinados com AND e a paginação
# é via limit/offset. Escrita (itens 21 e 29): create_*/update_* via POST/PUT,
# limite 500/dia por rota; não há DELETE nem edição/conclusão de tarefa na API.
class Ramon::AdvboxClient
  class UnavailableError < StandardError; end

  # 4xx com corpo — o chamador decide (ex.: 422 de CPF duplicado no POST /customers).
  class RequestError < StandardError
    attr_reader :code, :body

    def initialize(code, body)
      @code = code
      @body = body
      super("AdvBox respondeu HTTP #{code}")
    end

    def duplicate?
      code == 422 && body.to_s.match?(/duplicate/i)
    end
  end

  BASE = 'https://app.advbox.com.br/api/v1'.freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20
  # Tudo que é falha transitória de rede/TLS vira UnavailableError (retry no
  # job) — fora da lista cairia no rescue genérico do chamador como erro
  # permanente (ECONNRESET do Cloudflare é o caso comum).
  NETWORK_ERRORS = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, Errno::ETIMEDOUT,
                    SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError, JSON::ParserError].freeze

  def self.lawsuits(params = {})
    get('/lawsuits', params)
  end

  def self.lawsuit(id)
    get("/lawsuits/#{id}")
  end

  def self.movements(lawsuit_id, limit: 8)
    get("/movements/#{lawsuit_id}", limit: limit)
  end

  def self.publications(lawsuit_id, limit: 2)
    get("/publications/#{lawsuit_id}", limit: limit)
  end

  def self.history(lawsuit_id)
    get("/history/#{lawsuit_id}")
  end

  def self.last_movements(params = {})
    get('/last_movements', params)
  end

  def self.customers(params = {})
    get('/customers', params)
  end

  def self.customer(id)
    get("/customers/#{id}")
  end

  # "Posts" na API do AdvBox = tarefas/anotações (inclusive com prazo:
  # deadline_start/deadline_end filtram o vencimento).
  def self.posts(params = {})
    get('/posts', params)
  end

  # IDs de configuração da conta (users, stages, tasks, lawsuit_types, origins,
  # financial) — referência obrigatória pra qualquer escrita.
  def self.settings
    get('/settings')
  end

  def self.create_customer(body)
    post('/customers', body)
  end

  def self.create_lawsuit(body)
    post('/lawsuits', body)
  end

  def self.create_post(body)
    post('/posts', body)
  end

  # Movimentação/andamento manual. A API exige date em DD/MM/YYYY e description
  # com ao menos 10 caracteres.
  def self.create_movement(body)
    post('/lawsuits/movement', body)
  end

  def self.create_transaction(body)
    post('/transactions', body)
  end

  def self.update_lawsuit(id, body)
    put("/lawsuits/#{id}", body)
  end

  def self.update_transaction(id, body)
    put("/transactions/#{id}", body)
  end

  def self.get(path, params = {})
    response = HTTParty.get("#{BASE}#{path}",
                            query: params,
                            headers: headers,
                            open_timeout: OPEN_TIMEOUT,
                            read_timeout: READ_TIMEOUT)
    raise UnavailableError, "AdvBox respondeu HTTP #{response.code}" unless response.success?

    response.parsed_response
  rescue *NETWORK_ERRORS => e
    raise UnavailableError, "AdvBox indisponível: #{e.message}"
  end
  private_class_method :get

  def self.post(path, body)
    write(:post, path, body)
  end
  private_class_method :post

  def self.put(path, body)
    write(:put, path, body)
  end
  private_class_method :put

  def self.write(verb, path, body)
    response = HTTParty.public_send(verb, "#{BASE}#{path}",
                                    body: body.to_json,
                                    headers: headers.merge('Content-Type' => 'application/json'),
                                    open_timeout: OPEN_TIMEOUT,
                                    read_timeout: READ_TIMEOUT)
    return response.parsed_response if response.success?
    raise UnavailableError, "AdvBox respondeu HTTP #{response.code}" if response.code >= 500

    raise RequestError.new(response.code, response.parsed_response)
  rescue *NETWORK_ERRORS => e
    raise UnavailableError, "AdvBox indisponível: #{e.message}"
  end
  private_class_method :write

  def self.headers
    token = ENV.fetch('ADVBOX_API_TOKEN', nil)
    raise UnavailableError, 'AdvBox indisponível: ADVBOX_API_TOKEN não configurado' if token.blank?

    { 'Authorization' => "Bearer #{token}",
      'Accept' => 'application/json',
      'User-Agent' => 'ramon-hub/1.0' }
  end
  private_class_method :headers
end
