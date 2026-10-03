# "Quem vem hoje" pra Recepção: tarefas ATENDIMENTO do dia no ADVBOX, com o
# responsável casado ao usuário do hub por e-mail. A API do ADVBOX tem cota de
# 500 chamadas/dia (compartilhada) → agenda em cache de 10 min, settings de 24 h (Ramon::AdvboxUsuarios).
class Ramon::AgendaHojeService
  TAREFA = 'ATENDIMENTO'.freeze
  # ponytail: origem que o ADVBOX põe nas partes contrárias (INSS etc.) nesta conta;
  # se errar, a Gabriela corrige o nome no campo antes de avisar.
  PARTE_CONTRARIA = 25_705

  def initialize(account)
    @account = account
  end

  def perform
    tarefas_de_hoje.map { |tarefa| linha(tarefa) }
  end

  private

  def tarefas_de_hoje
    hoje = Time.find_zone!(Chegada::ZONA).today.iso8601
    Rails.cache.fetch("ramon/agenda_hoje/#{hoje}", expires_in: 10.minutes) do
      resposta = Ramon::AdvboxClient.posts(date_start: hoje, date_end: hoje, limit: 100)
      Array(resposta.is_a?(Hash) ? resposta['data'] : resposta).select { |tarefa| tarefa['task'] == TAREFA }
    end
  end

  def linha(tarefa)
    cliente = Array(tarefa.dig('lawsuit', 'customers')).find { |c| c['customers_origins_id'] != PARTE_CONTRARIA }
    responsavel = Array(tarefa['users']).first || {}
    {
      advbox_post_id: tarefa['id'], cliente_nome: cliente&.dig('name'), advbox_customer_id: cliente&.dig('customer_id'),
      hora: Ramon::SemanaAdvboxService.hora(tarefa['date']), notas: tarefa['notes'], responsavel_advbox: responsavel['name'],
      destinatario_id: Ramon::AdvboxUsuarios.usuario(@account, responsavel['user_id'])&.id
    }
  end
end
