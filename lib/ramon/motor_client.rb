# Cliente HTTP do motor de cálculos previdenciários (serviço FastAPI externo,
# ex.: http://motor:8000 na VPS). Sem ENV ou com o serviço fora do ar, levanta
# UnavailableError — o simulador degrada com mensagem clara, sem quebrar o hub.
class Ramon::MotorClient
  class UnavailableError < StandardError; end
  class ValidationError < StandardError; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15
  # Parse de PDF grande (pdfplumber) é mais lento que um cálculo.
  CNIS_READ_TIMEOUT = 60

  def self.incapacidade(payload)
    base = ENV.fetch('MOTOR_CALCULOS_URL', nil)
    raise UnavailableError, 'motor indisponível: MOTOR_CALCULOS_URL não configurada' if base.blank?

    response = HTTParty.post("#{base.chomp('/')}/incapacidade",
                             headers: { 'Content-Type' => 'application/json' },
                             body: payload.to_json,
                             open_timeout: OPEN_TIMEOUT,
                             read_timeout: READ_TIMEOUT)
    handle(response)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Timeout::Error => e
    raise UnavailableError, "motor indisponível: #{e.message}"
  end

  # arquivo = upload Rack/ActionDispatch (respond_to? :read/:path) — HTTParty monta o multipart.
  def self.cnis(arquivo, sexo:)
    base = ENV.fetch('MOTOR_CALCULOS_URL', nil)
    raise UnavailableError, 'motor indisponível: MOTOR_CALCULOS_URL não configurada' if base.blank?

    response = HTTParty.post("#{base.chomp('/')}/cnis",
                             multipart: true,
                             body: { arquivo: arquivo, sexo: sexo },
                             open_timeout: OPEN_TIMEOUT,
                             read_timeout: CNIS_READ_TIMEOUT)
    handle(response)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Timeout::Error => e
    raise UnavailableError, "motor indisponível: #{e.message}"
  end

  def self.handle(response)
    return response.parsed_response if response.success?
    raise ValidationError, detail_de(response) if response.code == 422

    raise UnavailableError, "motor indisponível: respondeu HTTP #{response.code}"
  end

  def self.detail_de(response)
    detail = response.parsed_response.is_a?(Hash) ? response.parsed_response['detail'] : nil
    (detail.presence || response.body).to_s
  end
  private_class_method :handle, :detail_de
end
