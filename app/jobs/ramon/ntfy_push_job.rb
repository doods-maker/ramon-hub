# O ntfy.sh é um servidor PÚBLICO: quem souber o tópico lê. Título e corpo levam só a tese,
# o tipo de evento e horários — nome, telefone, CPF e nº de processo ficam no hub.
class Ramon::NtfyPushJob < ApplicationJob
  queue_as :low

  # Pedaços do nome que não identificam ninguém (e "lead", do nome provisório "Lead #12").
  FORA_DO_NOME = %w[das dos lead].freeze

  # Como um lead aparece no push: pela tese (o nome fica no sino do hub).
  def self.rotulo(lead) = lead&.thesis&.name.presence || 'Lead'

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
    req['Title'] = ascii_title(sem_nome(custom_title, lead).presence || 'Novo lead')
    req['Tags'] = 'bell'
    req.body = sem_nome(custom_body, lead).presence || body_for(lead)
    http.request(req)
  end

  # Guarda única da regra do topo: o nome do lead (e o do contato) que algum chamador pôs no texto sai como a tese.
  # Vale para o nome inteiro e para cada parte dele (com e sem acento), só como palavra inteira ("Ana" não mexe em
  # "semana"). ponytail: não alcança apelido nem dado pessoal em texto livre do chamador (telefone, CPF); quem monta
  # push novo usa `rotulo`.
  def sem_nome(texto, lead)
    return texto.to_s if lead.nil?

    partes_do_nome(lead).reduce(texto.to_s) do |limpo, nome|
      limpo.gsub(/(?<![[:alnum:]])#{Regexp.escape(nome)}(?![[:alnum:]])/i, self.class.rotulo(lead))
    end
  end

  # Mais longa primeiro: o nome inteiro vira um rótulo só, não um por parte.
  def partes_do_nome(lead)
    nomes = [lead.name, lead.contact&.name].compact_blank
    partes = (nomes + nomes.flat_map(&:split)).flat_map { |nome| [nome, I18n.transliterate(nome)] }.uniq
    partes.reject { |nome| nome.length < 3 || FORA_DO_NOME.include?(nome.downcase) }.sort_by { |nome| -nome.length }
  end

  # Header HTTP não aceita não-ASCII → transliterar (acentos) p/ ASCII;
  # '·' (separador padrão dos títulos) viraria '?' — mapear pra '-'.
  def ascii_title(title)
    I18n.transliterate(title.tr('·', '-'))
  end

  # O corpo pode ter acentos normalmente (é o payload, não header).
  def body_for(lead)
    parts = [lead.thesis&.name, via_line_for(lead)]
    parts.compact.join(' · ').presence || 'Lead sem detalhes'
  end

  def via_line_for(lead)
    source = lead.channel.presence || lead.source.presence
    "via #{source}" if source
  end
end
