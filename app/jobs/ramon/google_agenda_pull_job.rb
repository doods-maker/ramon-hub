# Traz do Google para o hub as reuniões movidas ou canceladas lá (a cada 5 min). Evento sem reunião do hub
# (compromisso pessoal) é ignorado. O hub aplica sem empurrar de volta (sem_google). Logs: só classe e ids (LGPD).
class Ramon::GoogleAgendaPullJob < ApplicationJob
  queue_as :scheduled_jobs

  Cliente = Ramon::GoogleAgenda::Cliente

  TOLERANCIA = 60 # segundos

  def perform
    GoogleAgendaConta.conectadas.find_each do |conta|
      sincronizar(conta)
    rescue Cliente::SemConexao
      next
    rescue Ramon::GoogleAgenda::Token::Transitorio
      Rails.logger.warn("GoogleAgendaPullJob: Google instável conta_id=#{conta.id}") # tenta de novo em 5 min
    rescue StandardError => e
      Rails.logger.error("GoogleAgendaPullJob: #{e.class} conta_id=#{conta.id} user_id=#{conta.user_id}")
      ChatwootExceptionTracker.new(e).capture_exception
    end
  end

  private

  def sincronizar(conta)
    Cliente.new(conta).eventos(de: 1.day.ago, ate: 30.days.from_now).each do |evento|
      task = tarefa_de(conta, evento)
      aplicar(task, evento) if task
    end
    conta.update_columns(ultima_sincronizacao_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Reunião aberta do dono da agenda: pelo hub_task_id ou, no cancelado mínimo (sem propriedades), pelo id do evento.
  def tarefa_de(conta, evento)
    tarefas = LeadTask.open_tasks.where(kind: 'meeting', agenda_user_id: conta.user_id)
    (evento[:hub_task_id] && tarefas.find_by(id: evento[:hub_task_id])) ||
      (evento[:id].present? && tarefas.find_by(google_event_id: evento[:id]))
  end

  # Google mais velho que a tarefa = o hub mudou e o push ainda não chegou lá: não desfaz a ação do hub.
  # ponytail: compara relógios do Google e do hub; mudança no Google seguida de edição no hub em < 5 min se perde.
  def aplicar(task, evento)
    return if evento[:atualizado_em] && evento[:atualizado_em] <= task.updated_at

    if evento[:cancelado]
      Ramon::ReuniaoAgendamento.cancelar(task: task, sem_google: true)
    elsif evento[:inicio] && (evento[:inicio] - task.due_at).abs > TOLERANCIA
      Ramon::ReuniaoAgendamento.remarcar(task: task, starts_at: evento[:inicio], sem_google: true)
    end
  end
end
