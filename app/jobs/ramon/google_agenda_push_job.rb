# Leva a reunião do hub (LeadTask meeting) para o Google do dono da agenda: criar, atualizar ou cancelar.
# Sem dono ou sem conta Google conectada, sai calado (a reunião vive só no hub). Logs: só classe e ids (LGPD).
class Ramon::GoogleAgendaPushJob < ApplicationJob
  queue_as :default

  Cliente = Ramon::GoogleAgenda::Cliente

  TITULO = 'Conversa com Ramon Antonio Advogados'.freeze
  # Texto do convite APROVADO pelo Eduardo em 16/10 (parágrafo do Meet sai na ligação pelo WhatsApp).
  CONVITE = <<~TEXTO.strip.freeze
    Olá, %<primeiro_nome>s! Esta é a nossa conversa sobre o seu caso, com %<nome_do_closer>s.

    %<meio>s

    Se não puder comparecer, avise pelo WhatsApp que a gente remarca sem problema.
  TEXTO
  MEIO_VIDEO = 'Para entrar, é só tocar no link do Google Meet no horário marcado. Se preferir, a gente liga no seu WhatsApp.'.freeze
  # ponytail: frase aprovada da confirmação (variante WhatsApp); uso no convite aguarda o ok do Eduardo
  MEIO_WHATSAPP = 'Eu te ligo no WhatsApp nesse horário.'.freeze

  retry_on Ramon::GoogleAgenda::Token::Transitorio, wait: 1.minute, attempts: 3 do |job, erro|
    Rails.logger.error("GoogleAgendaPushJob: #{erro.class} esgotou as tentativas task_id=#{job.arguments.last['task_id']}")
  end

  def perform(acao, dados)
    @dados = dados
    acao == 'cancelar' ? cancelar : empurrar(acao)
  rescue Cliente::SemConexao
    nil
  rescue Ramon::GoogleAgenda::Token::Transitorio
    raise # o retry_on cuida
  rescue StandardError => e
    Rails.logger.error("GoogleAgendaPushJob: #{e.class} #{acao} task_id=#{dados['task_id']}")
    ChatwootExceptionTracker.new(e).capture_exception
  end

  private

  def cancelar
    conta = conta_de(User.find_by(id: @dados['agenda_user_id']))
    Cliente.new(conta).cancelar(@dados['google_event_id']) if conta && @dados['google_event_id'].present?
  end

  def empurrar(acao)
    task = LeadTask.find_by(id: @dados['task_id'])
    conta = task && conta_de(task.agenda_user)
    return if conta.nil?

    cliente = Cliente.new(conta)
    return criar(cliente, task) if acao == 'criar' && task.google_event_id.blank? && task.completed_at.nil?

    atualizar(cliente, task) if acao == 'atualizar'
  end

  def conta_de(user) = user && GoogleAgendaConta.de(user)

  def criar(cliente, task)
    evento = cliente.criar(inicio: task.due_at, fim: task.due_at + LeadTask::DURACAO, titulo: TITULO, descricao: descricao(task),
                           meet: task.formato == 'video', convidado_email: task.lead.contact&.email.presence, hub_task_id: task.id,
                           id: "hubtask#{task.id}") # base32hex (0-9a-v, 5+): repetir a criação não duplica o evento
    gravar_evento(task, evento)
  rescue Cliente::Erro => e
    raise unless e.code == 409 # já existe (tentativa anterior chegou ao Google): busca e grava

    gravar_evento(task, cliente.evento("hubtask#{task.id}"))
  end

  def gravar_evento(task, evento)
    task.update_columns(google_event_id: evento[:id], meet_url: evento[:meet_url]) # rubocop:disable Rails/SkipsModelValidations
  end

  # Sem evento no Google (nunca chegou a nascer) → nasce agora. Troca de formato vai junto do horário.
  def atualizar(cliente, task)
    return if task.completed_at.present?
    return criar(cliente, task) if task.google_event_id.blank?

    mover(cliente, task, task.google_event_id)
  end

  def mover(cliente, task, id)
    base = { inicio: task.due_at, fim: task.due_at + LeadTask::DURACAO }
    if task.formato == 'video' && task.meet_url.blank?
      task.update_columns(meet_url: cliente.atualizar(id, **base, meet: true, descricao: descricao(task))) # rubocop:disable Rails/SkipsModelValidations
    elsif task.formato == 'whatsapp' && task.meet_url.present?
      cliente.atualizar(id, **base, meet: false, descricao: descricao(task))
      task.update_columns(meet_url: nil) # rubocop:disable Rails/SkipsModelValidations
    else
      cliente.atualizar(id, **base)
    end
  end

  def descricao(task)
    format(CONVITE, primeiro_nome: task.lead.name.to_s.split.first.presence || 'cliente', nome_do_closer: task.agenda_user.name,
                    meio: task.formato == 'video' ? MEIO_VIDEO : MEIO_WHATSAPP)
  end
end
