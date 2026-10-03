# "Quem vem hoje" pra Recepção: tarefas ATENDIMENTO do dia no ADVBOX, com o
# responsável casado ao usuário do hub por e-mail. A API do ADVBOX tem cota de
# 500 chamadas/dia (compartilhada) → agenda em cache de 10 min, settings de 24 h.
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
      notas: tarefa['notes'], responsavel_advbox: responsavel['name'], destinatario_id: usuario_do_hub(responsavel['user_id'])&.id
    }
  end

  def usuario_do_hub(advbox_user_id)
    email = emails_advbox[advbox_user_id]
    email && @account.users.find_by('LOWER(users.email) = ?', email.downcase)
  end

  def emails_advbox
    @emails_advbox ||= Rails.cache.fetch('ramon/advbox_users_email', expires_in: 24.hours) do
      Array(Ramon::AdvboxClient.settings['users']).to_h { |user| [user['id'], user['email']] }
    end
  end
end
