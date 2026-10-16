# Leva a reunião do hub (LeadTask meeting) para o Google do dono da agenda: criar, atualizar ou cancelar.
# Sem dono ou sem conta Google conectada, sai calado (a reunião vive só no hub). Logs: só classe e ids (LGPD).
# Marcação com conta Google: o rascunho de confirmação nasce aqui, depois do Meet (dados 'rascunho'); se o Google falhar, nasce sem Meet.
class Ramon::GoogleAgendaPushJob < ApplicationJob
  queue_as :default

  Cliente = Ramon::GoogleAgenda::Cliente

  Convite = Ramon::Agenda::Convite

  retry_on Ramon::GoogleAgenda::Token::Transitorio, wait: 1.minute, attempts: 3 do |job, erro|
    Rails.logger.error("GoogleAgendaPushJob: #{erro.class} esgotou as tentativas task_id=#{job.arguments.last['task_id']}")
    job.rascunho_sem_meet
  end

  def perform(acao, dados)
    @dados = dados
    acao == 'cancelar' ? cancelar : empurrar(acao)
  rescue Cliente::SemConexao
    rascunho_sem_meet
  rescue Ramon::GoogleAgenda::Token::Transitorio
    raise # o retry_on cuida
  rescue StandardError => e
    Rails.logger.error("GoogleAgendaPushJob: #{e.class} #{acao} task_id=#{dados['task_id']}")
    ChatwootExceptionTracker.new(e).capture_exception
    rascunho_sem_meet
  end

  # A pessoa nunca fica sem rascunho: Google fora do ar → confirmação sem a linha do Meet.
  def rascunho_sem_meet
    task = @dados && LeadTask.find_by(id: @dados['task_id'])
    rascunhar(task) if task
  end

  private

  def cancelar
    conta = conta_de(User.find_by(id: @dados['agenda_user_id']))
    Cliente.new(conta).cancelar(@dados['google_event_id']) if conta && @dados['google_event_id'].present?
  end

  def empurrar(acao)
    task = LeadTask.find_by(id: @dados['task_id'])
    conta = task && conta_de(task.agenda_user)
    return rascunho_sem_meet if conta.nil?

    cliente = Cliente.new(conta)
    return criar(cliente, task) if acao == 'criar' && task.google_event_id.blank? && task.completed_at.nil?

    atualizar(cliente, task) if acao == 'atualizar'
  end

  def conta_de(user) = user && GoogleAgendaConta.de(user)

  def criar(cliente, task)
    criar_evento(cliente, task)
    rascunhar(task)
  end

  def rascunhar(task)
    return unless @dados['rascunho'] && !@rascunhado

    @rascunhado = true
    Ramon::ReuniaoAgendamento.confirmar(task, automatico: @dados['automatico'] == true)
  end

  def criar_evento(cliente, task)
    evento = cliente.criar(inicio: task.due_at, fim: task.due_at + LeadTask::DURACAO, titulo: Convite::TITULO,
                           descricao: Convite.new(task).descricao, meet: task.formato == 'video',
                           convidado_email: task.lead.contact&.email.presence, hub_task_id: task.id,
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
      meet = cliente.atualizar(id, **base, meet: true, descricao: Convite.new(task).descricao)
      task.update_columns(meet_url: meet) # rubocop:disable Rails/SkipsModelValidations
    elsif task.formato == 'whatsapp' && task.meet_url.present?
      cliente.atualizar(id, **base, meet: false, descricao: Convite.new(task).descricao)
      task.update_columns(meet_url: nil) # rubocop:disable Rails/SkipsModelValidations
    else
      cliente.atualizar(id, **base)
    end
  end
end
