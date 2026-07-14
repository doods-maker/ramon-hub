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

  # arquivo = upload Rack/ActionDispatch (respond_to? :read) — multipart montado
  # pelo stdlib (Net::HTTP#set_form): o corpo que o HTTParty monta à mão é
  # rejeitado pelo parser estrito do motor (python-multipart 0.0.32: "invalid
  # character 13 in header" → 400, que aparecia como "motor indisponível").
  # excluir_seqs ("3,7") e mensalidades (JSON {"5":"1286.00"}) vão crus: quem valida é o motor (422).
  def self.cnis(arquivo, sexo:, excluir_seqs: nil, mensalidades: nil)
    base = ENV.fetch('MOTOR_CALCULOS_URL', nil)
    raise UnavailableError, 'motor indisponível: MOTOR_CALCULOS_URL não configurada' if base.blank?

    uri = URI("#{base.chomp('/')}/cnis")
    form = [['arquivo', arquivo, { filename: arquivo.original_filename,
                                   content_type: arquivo.content_type.presence || 'application/pdf' }],
            ['sexo', sexo]]
    form << ['excluir_seqs', excluir_seqs] if excluir_seqs.present?
    form << ['mensalidades', mensalidades] if mensalidades.present?
    request = Net::HTTP::Post.new(uri)
    request.set_form(form, 'multipart/form-data')
    response = Net::HTTP.start(uri.hostname, uri.port,
                               open_timeout: OPEN_TIMEOUT,
                               read_timeout: CNIS_READ_TIMEOUT) { |http| http.request(request) }
    handle_net(response)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Timeout::Error, Net::ReadTimeout => e
    raise UnavailableError, "motor indisponível: #{e.message}"
  end

  def self.handle(response)
    return response.parsed_response if response.success?
    raise ValidationError, detail_de(response) if response.code == 422

    raise UnavailableError, "motor indisponível: respondeu HTTP #{response.code}"
  end

  def self.handle_net(response)
    parsed = begin
      JSON.parse(response.body)
    rescue JSON::ParserError, TypeError
      nil
    end
    return parsed if response.is_a?(Net::HTTPSuccess)

    if %w[400 422].include?(response.code)
      detail = parsed.is_a?(Hash) ? parsed['detail'] : nil
      raise ValidationError, (detail.presence || response.body).to_s
    end

    raise UnavailableError, "motor indisponível: respondeu HTTP #{response.code}"
  end

  def self.detail_de(response)
    detail = response.parsed_response.is_a?(Hash) ? response.parsed_response['detail'] : nil
    (detail.presence || response.body).to_s
  end
  private_class_method :post_json, :handle, :handle_net, :detail_de
end
