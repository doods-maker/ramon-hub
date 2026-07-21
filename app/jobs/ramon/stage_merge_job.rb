# Apagar/fundir etapa do funil: mover centenas de leads no request travava o
# Puma — a validação fica no controller, a movimentação vem pra cá. O board se
# atualiza pelos broadcasts `lead.updated` que cada update! já dispara.
class Ramon::StageMergeJob < ApplicationJob
  queue_as :low

  def perform(stage_id, target_id, user_id = nil)
    stage = LeadStage.find_by(id: stage_id)
    target = LeadStage.find_by(id: target_id)
    if stage.blank? || target.blank? || stage.id == target.id
      Rails.logger.warn("StageMergeJob: etapa/destino ausente (stage=#{stage_id} target=#{target_id}) — nada movido")
      return
    end

    # Autoria das atividades stage_changed (no request era o admin logado).
    Current.user = User.find_by(id: user_id)
    # Sem transação global: retry retoma de onde parou (leads já movidos saem
    # do escopo). StageLabelSync roda via listener do lead_updated — o chamado
    # explícito que dobrava o trabalho por lead morreu junto com o caminho síncrono.
    stage.leads.find_each { |lead| lead.update!(lead_stage: target) }
    deleted_label = stage.label
    stage.destroy!
    stage.account.labels.find_by(title: deleted_label)&.destroy
  ensure
    Current.reset
  end
end
