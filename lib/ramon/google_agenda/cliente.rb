# Cliente HTTP da Google Calendar API (agenda primária do usuário conectado).
# Token vem de Token.valido; 401 → uma renovação e uma nova tentativa. 429/5xx/rede → Transitorio; resto → Erro.
class Ramon::GoogleAgenda::Cliente
  class SemConexao < StandardError; end
  Transitorio = Ramon::GoogleAgenda::Token::Transitorio

  class Erro < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super("Google Calendar respondeu HTTP #{code}")
    end
  end

  BASE = 'https://www.googleapis.com/calendar/v3/calendars/primary/events'.freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20
  REDE = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, Errno::ETIMEDOUT,
          SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError].freeze

  def initialize(conta)
    @conta = conta
  end

  def eventos(de:, ate:) # rubocop:disable Naming/MethodParameterName
    itens = []
    pagina = nil
    loop do
      query = { singleEvents: true, orderBy: 'startTime', showDeleted: true, timeMin: de.iso8601, timeMax: ate.iso8601 }
      query[:pageToken] = pagina if pagina
      corpo = requisitar(:get, '', query: query)
      itens.concat(Array(corpo['items']).filter_map { |e| mapear(e) })
      pagina = corpo['nextPageToken']
      break if pagina.blank?
    end
    itens
  end

  def criar(inicio:, fim:, titulo:, descricao:, meet:, hub_task_id:, convidado_email: nil) # rubocop:disable Metrics/ParameterLists
    corpo = { summary: titulo, description: descricao, start: { dateTime: inicio.iso8601 }, end: { dateTime: fim.iso8601 },
              extendedProperties: { private: { hub_task_id: hub_task_id.to_s } } }
    corpo[:attendees] = [{ email: convidado_email }] if convidado_email.present?
    corpo[:conferenceData] = { createRequest: { requestId: "hub-#{hub_task_id}" } } if meet
    query = { conferenceDataVersion: 1, sendUpdates: convidado_email.present? ? 'all' : 'none' }
    evento = requisitar(:post, '', query: query, body: corpo)
    { id: evento['id'], meet_url: meet_url(evento) }
  end

  def atualizar(id, inicio:, fim:)
    corpo = { start: { dateTime: inicio.iso8601 }, end: { dateTime: fim.iso8601 } }
    requisitar(:patch, "/#{ERB::Util.url_encode(id)}", query: { sendUpdates: 'all' }, body: corpo)
    true
  end

  def cancelar(id)
    requisitar(:delete, "/#{ERB::Util.url_encode(id)}", query: { sendUpdates: 'all' }, ignorar: [404, 410])
    true
  end

  private

  # Cancelado pode vir só com id/status (sem horário): volta com inicio/fim nil — quem sincroniza casa pelo id.
  def mapear(evento)
    inicio = hora(evento['start'])
    fim = hora(evento['end'])
    cancelado = evento['status'] == 'cancelled'
    return nil unless cancelado || (inicio && fim)

    { id: evento['id'], inicio: inicio, fim: fim, titulo: evento['summary'], cancelado: cancelado,
      hub_task_id: evento.dig('extendedProperties', 'private', 'hub_task_id').presence&.to_i,
      atualizado_em: Time.zone.parse(evento['updated'].to_s) }
  end

  # Dia inteiro vem em date (fim exclusivo); com hora vem em dateTime.
  def hora(campo)
    return nil if campo.blank?

    campo['dateTime'] ? Time.zone.parse(campo['dateTime']) : Time.zone.parse(campo['date'].to_s)&.beginning_of_day
  end

  def meet_url(evento)
    return evento['hangoutLink'] if evento['hangoutLink'].present?

    Array(evento.dig('conferenceData', 'entryPoints')).find { |p| p['entryPointType'] == 'video' }&.dig('uri')
  end

  def requisitar(verb, caminho, query: {}, body: nil, ignorar: [])
    renovou = false
    loop do
      token = Ramon::GoogleAgenda::Token.valido(@conta)
      raise SemConexao if token.nil?

      resposta = enviar(verb, caminho, token, query, body)
      if resposta.code == 401
        raise Erro, 401 if renovou

        renovou = true
        raise SemConexao if Ramon::GoogleAgenda::Token.renovar(@conta).nil?

        next
      end
      return tratar(resposta, ignorar)
    end
  end

  def tratar(resposta, ignorar)
    return resposta.parsed_response if resposta.success? || ignorar.include?(resposta.code)
    raise Transitorio if resposta.code == 429 || resposta.code >= 500

    raise Erro, resposta.code
  end

  def enviar(verb, caminho, token, query, body)
    opts = { query: query, headers: { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' },
             open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT }
    if body
      opts[:body] = body.to_json
      opts[:headers]['Content-Type'] = 'application/json'
    end
    HTTParty.public_send(verb, "#{BASE}#{caminho}", **opts)
  rescue *REDE, Net::OpenTimeout, Net::ReadTimeout
    raise Transitorio
  end
end
