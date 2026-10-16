# Texto da reunião do hub para fora: título e descrição do convite (APROVADOS 16/10), link "Adicionar ao Google Agenda" e o
# .ics público assinado. O .ics e o link levam só o evento (título, horário, Meet) — nada do cliente.
class Ramon::Agenda::Convite
  TITULO = 'Conversa com Ramon Antonio Advogados'.freeze
  CONVITE = <<~TEXTO.strip.freeze
    Olá, %<primeiro_nome>s! Esta é a nossa conversa sobre o seu caso, com %<nome_do_closer>s.

    %<meio>s

    Se não puder comparecer, avise pelo WhatsApp que a gente remarca sem problema.
  TEXTO
  MEIO_VIDEO = 'Para entrar, é só tocar no link do Google Meet no horário marcado. Se preferir, a gente liga no seu WhatsApp.'.freeze
  MEIO_WHATSAPP = 'Eu te ligo no WhatsApp nesse horário.'.freeze
  GOOGLE = 'https://calendar.google.com/calendar/render'.freeze

  def initialize(task)
    @task = task
  end

  # Descrição do convite que o Google manda ao cliente (com o nome dele; só vai por e-mail do Google).
  def descricao
    format(CONVITE, primeiro_nome: @task.lead.name.to_s.split.first.presence || 'cliente', nome_do_closer: @task.agenda_user.name,
                    meio: @task.formato == 'video' ? MEIO_VIDEO : MEIO_WHATSAPP)
  end

  # Curto de propósito: o link vai dentro do rascunho (nota de 1000 caracteres).
  def detalhes
    return MEIO_WHATSAPP if @task.formato == 'whatsapp'

    @task.meet_url.present? ? "Google Meet: #{@task.meet_url}" : ''
  end

  def link_google
    "#{GOOGLE}?action=TEMPLATE&text=#{URI.encode_www_form_component(TITULO)}&dates=#{utc(inicio)}/#{utc(fim)}" \
      "&details=#{URI.encode_www_form_component(detalhes)}"
  end

  def link_ics
    "#{ENV.fetch('FRONTEND_URL', '')}/public/api/v1/agenda/#{@task.signed_id(purpose: :ics, expires_in: 60.days)}.ics"
  end

  def ics
    [
      'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Ramon Antonio Advogados//Agenda//PT', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
      'BEGIN:VEVENT', "UID:hub-#{@task.id}", "DTSTAMP:#{utc(Time.current)}", "DTSTART:#{utc(inicio)}", "DTEND:#{utc(fim)}",
      "SUMMARY:#{TITULO}", "DESCRIPTION:#{escapar(detalhes)}", ("LOCATION:#{escapar(@task.meet_url)}" if @task.meet_url.present?),
      'END:VEVENT', 'END:VCALENDAR'
    ].compact.join("\r\n") << "\r\n"
  end

  private

  def inicio = @task.due_at

  def fim = @task.due_at + LeadTask::DURACAO

  def utc(tempo) = tempo.utc.strftime('%Y%m%dT%H%M%SZ')

  def escapar(texto) = texto.to_s.gsub(/([\\;,])/) { "\\#{Regexp.last_match(1)}" }.gsub("\n", '\n')
end
