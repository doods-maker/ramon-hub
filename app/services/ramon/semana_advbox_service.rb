# "Sua semana no ADVBOX" (tela Hoje da advogada): tarefas dos próximos 7 dias da
# pessoa, com perícia/audiência em destaque (vêm como "ACOMPANHAR PERÍCIA" etc.).
# Uma busca a cada 30 min pra todo mundo (cota ADVBOX 500/dia compartilhada).
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

  def initialize(account)
    @account = account
  end

  def para(user)
    ids = Ramon::AdvboxUsuarios.ids_de(user)
    tarefas.select { |tarefa| Array(tarefa['users']).any? { |u| ids.include?(u['user_id']) } }
           .map { |tarefa| linha(tarefa) }
           .sort_by { |l| [l[:data], l[:hora].to_s] }
  end

  private

  def tarefas
    hoje = Time.find_zone!(Chegada::ZONA).today
    Rails.cache.fetch("ramon/semana_advbox/#{hoje.iso8601}", expires_in: 30.minutes) { buscar(hoje) }
  end

  # Envelope { offset, limit, totalCount, data } — pagina até vir lote incompleto.
  # ponytail: teto de PAGINAS (500 tarefas/semana); se a banca passar disso, subir o teto.
  def buscar(hoje)
    (0...PAGINAS).each_with_object([]) do |pagina, todas|
      resposta = Ramon::AdvboxClient.posts(date_start: hoje.iso8601, date_end: (hoje + 7).iso8601, limit: POR_PAGINA, offset: pagina * POR_PAGINA)
      lote = Array(resposta['data'])
      todas.concat(lote)
      break todas if lote.size < POR_PAGINA
    end
  end

  def linha(tarefa)
    cliente = Array(tarefa.dig('lawsuit', 'customers')).find { |c| c['customers_origins_id'] != Ramon::AgendaHojeService::PARTE_CONTRARIA }
    {
      data: tarefa['date'].to_s[0, 10], hora: self.class.hora(tarefa['date']), tarefa: tarefa['task'],
      destaque: DESTAQUE.find { |regex, _| tarefa['task'].to_s.match?(regex) }&.last,
      cliente: cliente&.dig('name'), processo: tarefa.dig('lawsuit', 'process_number'), notas: tarefa['notes']
    }
  end
end
