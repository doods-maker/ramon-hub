# Tela Hoje (09/11/2026): as tarefas do ADVBOX de quem está logado — hoje, os próximos 7 dias e as tarefas da
# esteira de petições ainda abertas (peça pronta para revisar ou caso parado). Uma busca por pessoa, de 2 semanas
# atrás até 7 dias à frente, em cache de 15 min: a cota do ADVBOX (500/dia) é compartilhada com o hub todo.
# A tarefa some daqui quando é concluída no ADVBOX; o hub não guarda nada.
class Ramon::MeuDiaAdvbox
  ATRAS = 14
  FRENTE = 7
  PAGINA = 100
  # ponytail: teto de 5 páginas (500 tarefas em 3 semanas); acima disso o resto não aparece.
  MAX_PAGINAS = 5
  # ponytail: a tarefa da esteira sempre abre com "SITUAÇÃO" e cita o .docx em Esteira/ (esteira-agentes,
  # vps/workspace/CLAUDE.md, "Fim do caso"). Se o prompt da esteira mudar, muda aqui.
  ESTEIRA = /\A\W*situação\b/i
  SITUACAO = /\A\W*situação\s*(?:\([^)\n]*\))?\s*:\s*(.*)/i
  PECA = %r{Esteira/([[:alnum:]][^/\n()]*?\.docx)}
  # 1ª frase: corta no ponto seguido de maiúscula (não em "art. 42" nem em "8.213").
  FRASE = /\A.*?\.(?=\s+[[:upper:]]|\s*\z)/
  VAZIO = { hoje: [], semana: [], esteira: [] }.freeze

  def initialize(account, user)
    @account = account
    @user = user
  end

  def perform
    return VAZIO if eu_no_advbox.nil?

    hoje = Time.find_zone!(Chegada::ZONA).today
    tarefas = minhas_tarefas(hoje)
    { hoje: do_dia(tarefas, hoje), semana: da_semana(tarefas, hoje), esteira: da_esteira(tarefas) }
  end

  private

  def do_dia(tarefas, hoje)
    tarefas.select { |t| dia(t) == hoje }.map { |t| linha(t) }
  end

  def da_semana(tarefas, hoje)
    tarefas.select { |t| aberta?(t) && dia(t)&.between?(hoje + 1, hoje + FRENTE) }.map { |t| linha(t) }
  end

  def da_esteira(tarefas)
    tarefas.select { |t| aberta?(t) && t['notes'].to_s.match?(ESTEIRA) }
           .sort_by { |t| t['created_at'].to_s }.reverse.map { |t| linha_esteira(t) }
  end

  def eu_no_advbox
    @eu_no_advbox ||= usuarios_advbox.find { |u| u['email'].to_s.casecmp?(@user.email.to_s) }
  end

  def usuarios_advbox
    Rails.cache.fetch('ramon/advbox_users', expires_in: 24.hours) do
      Array(Ramon::AdvboxClient.settings['users']).map { |u| u.slice('id', 'name', 'email') }
    end
  end

  # Só as tarefas em que a pessoa é responsável (o filtro por nome do ADVBOX é parcial), em ordem de data.
  def minhas_tarefas(hoje)
    Rails.cache.fetch("ramon/meu_dia/#{eu_no_advbox['id']}/#{hoje.iso8601}", expires_in: 15.minutes) do
      paginas(date_start: (hoje - ATRAS).iso8601, date_end: (hoje + FRENTE).iso8601)
        .select { |t| minha_atribuicao(t) }.uniq { |t| t['id'] }.sort_by { |t| [t['date'].to_s, t['id'].to_i] }
    end
  end

  def paginas(filtro)
    (0...MAX_PAGINAS).each_with_object([]) do |pagina, todas|
      resposta = Ramon::AdvboxClient.posts(filtro.merge(user_name: eu_no_advbox['name'], limit: PAGINA, offset: pagina * PAGINA))
      lote = Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
      total = resposta['totalCount'] if resposta.is_a?(Hash)
      todas.concat(lote)
      break todas if lote.size < PAGINA || (total && todas.size >= total.to_i)
    end
  end

  def minha_atribuicao(tarefa)
    Array(tarefa['users']).find { |u| u['user_id'] == eu_no_advbox['id'] }
  end

  def aberta?(tarefa)
    minha_atribuicao(tarefa)&.dig('completed').blank?
  end

  def dia(tarefa)
    Date.iso8601(tarefa['date'].to_s.first(10))
  rescue Date::Error
    nil
  end

  def linha(tarefa)
    {
      advbox_post_id: tarefa['id'], tarefa: tarefa['task'], cliente_nome: Ramon::AgendaHojeService.cliente_de(tarefa)&.dig('name'),
      data: tarefa['date'].to_s.first(10), prazo: tarefa['date_deadline'].to_s.first(10).presence, local: tarefa['local'].presence,
      concluida: !aberta?(tarefa)
    }
  end

  def linha_esteira(tarefa)
    notas = tarefa['notes'].to_s
    primeira_linha = notas[SITUACAO, 1].to_s
    {
      advbox_post_id: tarefa['id'], cliente_nome: Ramon::AgendaHojeService.cliente_de(tarefa)&.dig('name'),
      peca: notas[PECA, 1]&.strip, situacao: (primeira_linha[FRASE] || primeira_linha).truncate(200)
    }
  end
end
