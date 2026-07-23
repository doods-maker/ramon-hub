class Ramon::NtfyPushJob < ApplicationJob
  queue_as :low

  def perform(lead_id = nil, title: nil, body: nil)
    topic = ENV.fetch('NTFY_TOPIC', nil)
    return if topic.blank?           # feature desligada até o Eduardo setar o tópico

    lead = nil
    if lead_id.present?
      lead = Lead.find_by(id: lead_id)
      return if lead.blank?
    elsif title.blank? || body.blank?
      return # push sem lead (ex.: resumo diário) exige título e corpo prontos
    end

    server = ENV.fetch('NTFY_SERVER', 'https://ntfy.sh')
    post_ntfy(server, topic, lead, custom_title: title, custom_body: body)
  rescue StandardError => e
    # push é best-effort: nunca deixar um hiccup do ntfy quebrar o job/fila
    Rails.logger.warn("NtfyPushJob falhou p/ lead #{lead_id}: #{e.class} #{e.message}")
  end

  private

  def post_ntfy(server, topic, lead, custom_title: nil, custom_body: nil)
    uri = URI.join("#{server}/", topic)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 5

    req = Net::HTTP::Post.new(uri)
    req['Title'] = ascii_title(custom_title.presence || "Novo lead: #{lead.name}")
    req['Tags'] = 'bell'
    req.body = custom_body.presence || body_for(lead)
    http.request(req)
  end

  # Header HTTP não aceita não-ASCII → transliterar (acentos) p/ ASCII;
  # '·' (separador padrão dos títulos) viraria '?' — mapear pra '-'.
  def ascii_title(title)
    I18n.transliterate(title.tr('·', '-'))
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
