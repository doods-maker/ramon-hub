# Tela do Watchdog (Fatia 3 da área de IA): mostra o vigia que já roda — o
# rascunho de retomada diário (Ramon::DailyFollowUpJob, 11:00 BRT) e o copiloto
# noturno — com os limites visíveis, os contadores das últimas 24h e a lista
# dos casos em alerta. Não dispara nada: é leitura.
class Api::V1::Accounts::RamonWatchdogController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 50

  before_action :current_account
  before_action :check_authorization

  def show
    @thresholds = thresholds
    @counters = counters
    @items = em_alerta
  end

  private

  # Mesmas permissões do Centro de Comando (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  def thresholds
    {
      teto_diario: Ramon::FollowUpDraftService::DAILY_CAP,
      intervalo_minimo_dias: Ramon::FollowUpDraftService::MIN_GAP_DAYS,
      teto_copiloto_noturno: ENV.fetch('RAMON_NIGHT_COPILOT_LIMIT', '15').to_i,
      horario_retomada: '11:00 (BRT)',
      horario_copiloto: '05:00 (BRT)'
    }
  end

  def counters
    desde = 24.hours.ago
    {
      retomadas_24h: Current.account.lead_tasks.where(kind: 'follow_up', created_at: desde..).count,
      sugestoes_pendentes: Current.account.copilot_suggestions.pending.count,
      execucoes_24h: Captain::ToolRun.where(account_id: Current.account.id, created_at: desde..).count,
      parados_agora: parados.size
    }
  end

  def parados
    @parados ||= Ramon::LeadRadar.stalled_leads(Current.account).to_a
  end

  # Em alerta = parado no funil, ordenado por quem já levou mais tentativa de
  # retomada sem responder (é onde a régua está no limite).
  def em_alerta
    parados.map { |lead| row_for(lead) }
           .sort_by { |row| [-row[:tentativas], -row[:dias_parado]] }
           .first(LIST_LIMIT)
  end

  def row_for(lead)
    follow_up = lead.custom_attributes&.dig('follow_up') || {}
    {
      lead_id: lead.id,
      name: lead.name,
      stage_name: lead.lead_stage&.name,
      dias_parado: dias_parado(lead),
      limite_da_etapa: lead.lead_stage&.stalled_after_days,
      tentativas: follow_up['tentativas'].to_i,
      ultima_retomada_em: follow_up['ultima_em'],
      tarefa_aberta: lead.lead_tasks.open_tasks.exists?(kind: 'follow_up'),
      conversation_id: lead.conversation_id
    }
  end

  def dias_parado(lead)
    return 0 if lead.stage_entered_at.blank?

    (Time.zone.today - lead.stage_entered_at.to_date).to_i
  end
end
