# Cliente da API de Conversões da Meta para o funil (dataset da WABA). Só ids e valor saem: nada de dado do cliente.
# 429/5xx/rede → Transitorio; outro 4xx → Recusado (HTTP + error.code, sem corpo).
class Ramon::MetaCapi::Cliente
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20
  REDE = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, Errno::ETIMEDOUT,
          SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError].freeze

  def initialize(token:, waba_id:)
    @token = token
    @waba_id = waba_id
  end

  def dataset_id
    ENV['RAMON_META_DATASET_ID'].presence || Rails.cache.fetch("ramon/meta_capi/dataset/#{@waba_id}", expires_in: 1.day) { descobrir_dataset }
  end

  def enviar(evento:, event_id:, event_time:, ctwa_clid:, value: nil, test_event_code: nil) # rubocop:disable Metrics/ParameterLists
    item = { event_name: evento, event_time: event_time, event_id: event_id,
             action_source: 'business_messaging', messaging_channel: 'whatsapp',
             user_data: { whatsapp_business_account_id: @waba_id, ctwa_clid: ctwa_clid },
             custom_data: value ? { currency: 'BRL', value: value } : {} }
    corpo = { data: [item], access_token: @token }
    corpo[:test_event_code] = test_event_code if test_event_code.present?
    requisitar(:post, "#{dataset_id}/events", body: corpo.to_json)
    true
  end

  private

  def descobrir_dataset
    achado = Array(requisitar(:get, "#{@waba_id}/dataset")['data']).first
    (achado && achado['dataset_id']) || requisitar(:post, "#{@waba_id}/dataset", body: '{}')['id']
  end

  def requisitar(verb, caminho, query: nil, body: nil)
    opts = { headers: { 'Accept' => 'application/json', 'Authorization' => "Bearer #{@token}" },
             open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT }
    opts[:query] = query if query
    if body
      opts[:body] = body
      opts[:headers]['Content-Type'] = 'application/json'
    end
    resposta = HTTParty.public_send(verb, "#{Ramon::MetaCapi.base}/#{caminho}", **opts)
    return resposta.parsed_response if resposta.success?
    raise Ramon::MetaCapi::Transitorio, "HTTP #{resposta.code}" if resposta.code == 429 || resposta.code >= 500

    raise Ramon::MetaCapi::Recusado.new(resposta.code, codigo_meta(resposta))
  rescue *REDE, Net::OpenTimeout, Net::ReadTimeout
    raise Ramon::MetaCapi::Transitorio, 'rede'
  end

  def codigo_meta(resposta)
    corpo = resposta.parsed_response
    corpo.is_a?(Hash) ? corpo.dig('error', 'code') : nil
  end
end
