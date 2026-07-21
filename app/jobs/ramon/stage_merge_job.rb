# Apagar/fundir etapa do funil: mover centenas de leads no request travava o
# Puma — a validação fica no controller, a movimentação vem pra cá. O board se
# atualiza pelos broadcasts `lead.updated` que cada update! já dispara.
class Ramon::StageMergeJob < ApplicationJob
  queue_as :low

  def perform(stage_id, target_id)
    stage = LeadStage.find_by(id: stage_id)
    target = LeadStage.find_by(id: target_id)
    return if stage.blank? || target.blank? || stage.id == target.id

    # Sem transação global: retry retoma de onde parou (leads já movidos saem
    # do escopo). StageLabelSync roda via listener do lead_updated — o chamado
    # explícito que dobrava o trabalho por lead morreu junto com o caminho síncrono.
    stage.leads.find_each { |lead| lead.update!(lead_stage: target) }
    deleted_label = stage.label
    stage.destroy!
    stage.account.labels.find_by(title: deleted_label)&.destroy
  end
end
