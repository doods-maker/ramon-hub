# "Sua semana no ADVBOX" (tela Hoje da advogada): tarefas dos próximos 7 dias da
# pessoa, com perícia/audiência em destaque (vêm como "ACOMPANHAR PERÍCIA" etc.).
# Uma busca a cada 30 min pra todo mundo, via Ramon::AdvboxCache (cota 500/dia).
# Levanta erro se o ADVBOX falhar — quem chama trata.
class Ramon::SemanaAdvboxService
  DESTAQUE = { /PER[IÍ]CIA/i => 'pericia', /AUDI[EÊ]NCIA/i => 'audiencia' }.freeze
  POR_PAGINA = 100
  PAGINAS = 5

  # "2026-10-07 09:00:00" → "09:00"; 00:00 = tarefa sem hora.
  def self.hora(data)
    hora = data.to_s[11, 5]
    hora unless hora.blank? || hora == '00:00'
  end

  # Tarefas de todo mundo, hoje..hoje+6 (SP). Uma busca só pra semana da advogada e
  # pra agenda da Recepção (Ramon::AgendaHojeService filtra o dia daqui).
  def self.tarefas
    hoje = Time.find_zone!(Chegada::ZONA).today
    Ramon::AdvboxCache.buscar("ramon/semana_advbox/#{hoje.iso8601}", expires_in: 30.minutes) { buscar(hoje) }
  end

  # Envelope { offset, limit, totalCount, data }: pagina, sem repetir id, até o lote
  # vir incompleto/vazio/repetido ou bater o totalCount.
  # ponytail: teto de PAGINAS (500 tarefas/semana); se a banca passar disso, subir o teto.
  def self.buscar(hoje)
    (0...PAGINAS).each_with_object({}) do |pagina, por_id|
      lote, total = pagina(hoje, pagina)
      novas = lote.reject { |tarefa| por_id.key?(tarefa['id']) }
      novas.each { |tarefa| por_id[tarefa['id']] = tarefa }
      break por_id if fim?(novas, lote, total, por_id)
    end.values
  end

  def self.fim?(novas, lote, total, por_id)
    novas.empty? || lote.size < POR_PAGINA || (total.present? && por_id.size >= total)
  end

  def self.pagina(hoje, numero)
    resposta = Ramon::AdvboxClient.posts(date_start: hoje.iso8601, date_end: (hoje + 6).iso8601, limit: POR_PAGINA, offset: numero * POR_PAGINA)
    lote = Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
    [lote, resposta.is_a?(Hash) ? resposta['totalCount']&.to_i : nil]
  end
  private_class_method :buscar, :pagina, :fim?

  def initialize(account)
    @account = account
  end

  def para(user)
    ids = Ramon::AdvboxUsuarios.ids_de(user)
    self.class.tarefas.select { |tarefa| Array(tarefa['users']).any? { |u| ids.include?(u['user_id']) } }
        .map { |tarefa| linha(tarefa) }
        .sort_by { |l| [l[:data], l[:hora].to_s] }
  end

  # Painel do cliente na conversa (Ramon::ClienteDaConversa): mesmo cache da semana.
  def tarefas_do_processo(numero)
    self.class.tarefas.select { |tarefa| tarefa.dig('lawsuit', 'process_number') == numero }.map { |tarefa| linha(tarefa) }
  end

  private

  def linha(tarefa)
    cliente = Array(tarefa.dig('lawsuit', 'customers')).find { |c| c['customers_origins_id'] != Ramon::AgendaHojeService::PARTE_CONTRARIA }
    {
      data: tarefa['date'].to_s[0, 10], hora: self.class.hora(tarefa['date']), tarefa: tarefa['task'],
      destaque: DESTAQUE.find { |regex, _| tarefa['task'].to_s.match?(regex) }&.last,
      cliente: cliente&.dig('name'), processo: tarefa.dig('lawsuit', 'process_number'), notas: tarefa['notes']
    }
  end
end
