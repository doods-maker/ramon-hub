# Cliente HTTP da API do AdvBox (gestão processual da banca).
# Doc: https://api.softwareadvbox.com.br/docs — Bearer token, base /api/v1.
# Calibrado contra a API real 13/07/2026: busca parcial por nome do cliente em
# /lawsuits?name=, andamentos em /movements/{lawsuit_id} e publicações em
# /publications/{lawsuit_id}. O Cloudflare deles bloqueia requisição sem
# User-Agent — sempre mandar um.
class Ramon::AdvboxClient
  class UnavailableError < StandardError; end

  BASE = 'https://app.advbox.com.br/api/v1'.freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20

  def self.lawsuits(name:)
    get('/lawsuits', name: name)
  end

  def self.movements(lawsuit_id, limit: 8)
    get("/movements/#{lawsuit_id}", limit: limit)
  end

  def self.publications(lawsuit_id, limit: 2)
    get("/publications/#{lawsuit_id}", limit: limit)
  end

  def self.get(path, params = {})
    token = ENV.fetch('ADVBOX_API_TOKEN', nil)
    raise UnavailableError, 'AdvBox indisponível: ADVBOX_API_TOKEN não configurado' if token.blank?

    response = HTTParty.get("#{BASE}#{path}",
                            query: params,
                            headers: { 'Authorization' => "Bearer #{token}",
                                       'Accept' => 'application/json',
                                       'User-Agent' => 'ramon-hub/1.0' },
                            open_timeout: OPEN_TIMEOUT,
                            read_timeout: READ_TIMEOUT)
    raise UnavailableError, "AdvBox respondeu HTTP #{response.code}" unless response.success?

    response.parsed_response
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Timeout::Error => e
    raise UnavailableError, "AdvBox indisponível: #{e.message}"
  end
  private_class_method :get
end
