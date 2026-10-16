# Aviso de no-show (a cada 30 min): reunião aberta que passou de 2h sem registro → sino para o Closer + nota-rascunho de
# remarcação. NUNCA envia ao cliente e NUNCA marca a falta (complete!(no_show: true) é do Closer). 1 aviso por tarefa.
class Ramon::FunilNoShowJob < ApplicationJob
  queue_as :low

  def perform
    Account.find_each do |account|
      next if Ramon::FunilAutomatico.modo(account, 'no_show') == 'off'

      reunioes_passadas(account).find_each do |task|
        avisar(task)
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: account).capture_exception
        Rails.logger.error("FunilNoShowJob: tarefa #{task.id} do lead #{task.lead_id} falhou (#{e.class})") # sem e.message (LGPD)
      end
    end
  end

  private

  # Só de lead aberto: ganho ou perdido não tem remarcação a fazer.
  def reunioes_passadas(account)
    LeadTask.where(account: account, kind: 'meeting').open_tasks.where(due_at: 2.days.ago...2.hours.ago)
            .joins(:lead).where(leads: { lost_at: nil, won_at: nil }).includes(:lead)
  end

  # Conta o ensaio também: senão o ensaio registraria de novo a cada 30 min.
  def avisar(task)
    lead = task.lead
    return if FunilAcao.exists?(lead: lead, acao: 'avisar_no_show', alvo: task.id.to_s)

    quando = Ramon::ReuniaoAgendamento.quando(task.due_at)
    Ramon::FunilAutomatico.executar(lead, peca: 'no_show', acao: 'avisar_no_show', motivo: "Reunião de #{quando} sem registro",
                                          alvo: task.id.to_s) do
      notificar(lead, quando)
      lead.lead_notes.create!(account: lead.account, body: rascunho(lead, quando))
    end
  end

  # Aviso genérico de automação ("Automação: … (nome)"): o texto do lembrete de reunião pede "hora de confirmar".
  def notificar(lead, quando)
    destinatarios = [lead.closer_id].compact.presence || Ramon::Papeis.gestor_ids(lead.account)
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: destinatarios,
                                       meta: { 'label' => "reunião de #{quando} passou sem registro" }).perform
  end

  def rascunho(lead, quando)
    nome = lead.name.to_s.split.first.presence || 'cliente'
    "RASCUNHO (revisar antes de enviar) — remarcação:\n" \
      "\"Oi #{nome}! Senti sua falta na nossa conversa de #{quando}. Imagino que tenha surgido algum imprevisto. " \
      'Quer que a gente marque um novo horário?"'
  end
end
