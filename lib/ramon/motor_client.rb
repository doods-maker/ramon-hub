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
    post_json('/incapacidade', payload)
  end

  # Painel de possibilidades (estilo Previdenciarista): todos os cartões de
  # benefício, elegível ou não, com faltas e previsão de cumprimento.
  def self.painel(payload)
    post_json('/painel', payload, read_timeout: 30)
  end

  def self.post_json(path, payload, read_timeout: READ_TIMEOUT)
    base = ENV.fetch('MOTOR_CALCULOS_URL', nil)
    raise UnavailableError, 'motor indisponível: MOTOR_CALCULOS_URL não configurada' if base.blank?

    response = HTTParty.post("#{base.chomp('/')}#{path}",
                             headers: { 'Content-Type' => 'application/json' },
                             body: payload.to_json,
                             open_timeout: OPEN_TIMEOUT,
                             read_timeout: read_timeout)
    handle(response)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Timeout::Error => e
    raise UnavailableError, "motor indisponível: #{e.message}"
  end

  # arquivo = upload Rack/ActionDispatch (respond_to? :read/:path) — HTTParty monta o multipart.
  # excluir_seqs ("3,7") e mensalidades (JSON {"5":"1286.00"}) vão crus: quem valida é o motor (422).
  def self.cnis(arquivo, sexo:, excluir_seqs: nil, mensalidades: nil)
    base = ENV.fetch('MOTOR_CALCULOS_URL', nil)
    raise UnavailableError, 'motor indisponível: MOTOR_CALCULOS_URL não configurada' if base.blank?

    corpo = { arquivo: arquivo, sexo: sexo }
    corpo[:excluir_seqs] = excluir_seqs if excluir_seqs.present?
    corpo[:mensalidades] = mensalidades if mensalidades.present?
    response = HTTParty.post("#{base.chomp('/')}/cnis",
                             multipart: true,
                             body: corpo,
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
  private_class_method :post_json, :handle, :detail_de
end
