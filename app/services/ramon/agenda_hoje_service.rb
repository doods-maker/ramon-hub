# "Quem vem hoje" pra Recepção: tarefas ATENDIMENTO do dia no ADVBOX, com o
# responsável casado ao usuário do hub por e-mail. Cota do ADVBOX (500/dia): o dia sai
# do cache da semana e os e-mails do cache de 24 h, ambos via Ramon::AdvboxCache.
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

  # Mesmo cache da semana (Ramon::SemanaAdvboxService.tarefas) — sem chamada própria.
  def tarefas_de_hoje
    hoje = Time.find_zone!(Chegada::ZONA).today.iso8601
    Ramon::SemanaAdvboxService.tarefas.select { |tarefa| tarefa['task'] == TAREFA && tarefa['date'].to_s.start_with?(hoje) }
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
