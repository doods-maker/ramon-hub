# Ações em lote do Funil (mover etapa / atribuir SDR / follow-up / triagem IA).
# Roda em job pelo mesmo motivo do StageMergeJob: mover dezenas de leads no
# request travaria o Puma. O board se atualiza pelos broadcasts lead.updated
# que cada update!/lead_task já dispara — sem trabalho extra aqui.
class Ramon::LeadBulkActionJob < ApplicationJob
  queue_as :low

  FIELD_KEYS = %w[lead_stage_id sdr_id lost_reason].freeze

  def perform(account_id, user_id, params)
    account = Account.find(account_id)
    Current.account = account
    # Autoria das atividades (stage_changed, task_created) — como no request.
    Current.user = account.users.find_by(id: user_id)
    params = params.with_indifferent_access
    errors = []
    account.leads.where(id: params[:ids]).find_each do |lead|
      apply(lead, params)
    rescue StandardError => e
      # Erro por item não derruba o lote — log agregado no fim.
      errors << "lead=#{lead.id}: #{e.message}"
    end
    Rails.logger.warn("LeadBulkActionJob: #{errors.size} falha(s) — #{errors.join(' | ')}") if errors.any?
  ensure
    Current.reset
  end

  private

  def apply(lead, params)
    fields = (params[:fields] || {}).slice(*FIELD_KEYS).compact_blank
    lead.update!(fields) if fields.present?
    create_follow_up(lead, params[:task])
    run_triage(lead) if params[:triage].present?
  end

  def create_follow_up(lead, task)
    return if task.blank? || task[:due_at].blank?

    lead.lead_tasks.create!(
      account: lead.account,
      user: Current.user,
      kind: 'follow_up',
      title: task[:title].presence || 'Follow-up',
      due_at: task[:due_at]
    )
  end

  # Mesmo caminho do LeadTriagesController#create: cria a triagem com o agente
  # ativo padrão e deixa o TriageJob fazer o resto.
  def run_triage(lead)
    agent = lead.account.triage_agents.active.order(:id).first
    if agent.blank?
      Rails.logger.warn("LeadBulkActionJob: sem agente de triagem ativo (account=#{lead.account_id}) — triagem pulada")
      return
    end
    triage = lead.lead_triages.create!(account: lead.account, triage_agent: agent)
    Leads::TriageJob.perform_later(triage.id)
  end
end
