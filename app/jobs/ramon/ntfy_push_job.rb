class Ramon::NtfyPushJob < ApplicationJob
  queue_as :low

  def perform(lead_id)
    topic = ENV.fetch('NTFY_TOPIC', nil)
    return if topic.blank?           # feature desligada até o Eduardo setar o tópico

    lead = Lead.find_by(id: lead_id)
    return if lead.blank?

    server = ENV.fetch('NTFY_SERVER', 'https://ntfy.sh')
    post_ntfy(server, topic, lead)
  rescue StandardError => e
    # push é best-effort: nunca deixar um hiccup do ntfy quebrar o job/fila
    Rails.logger.warn("NtfyPushJob falhou p/ lead #{lead_id}: #{e.class} #{e.message}")
  end

  private

  def post_ntfy(server, topic, lead)
    uri = URI.join("#{server}/", topic)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 5

    req = Net::HTTP::Post.new(uri)
    req['Title'] = title_for(lead)        # header HTTP → só ASCII (ver abaixo)
    req['Tags'] = 'bell'
    req.body = body_for(lead)
    http.request(req)
  end

  # Header HTTP não aceita não-ASCII → transliterar o nome (acentos) p/ ASCII.
  def title_for(lead)
    I18n.transliterate("Novo lead: #{lead.name}")
  end

  # O corpo pode ter acentos normalmente (é o payload, não header).
  def body_for(lead)
    parts = [lead.benefit_type&.name || lead.thesis&.name, via_line_for(lead)]
    parts.compact.join(' · ').presence || 'Lead sem detalhes'
  end

  def via_line_for(lead)
    source = lead.channel.presence || lead.source.presence
    "via #{source}" if source
  end
end
