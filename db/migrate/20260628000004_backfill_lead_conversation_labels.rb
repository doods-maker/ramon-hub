class BackfillLeadConversationLabels < ActiveRecord::Migration[7.1]
  def up
    Ramon::StageLabelBackfill.perform
  end

  def down
    # Sem rollback de dados: as labels fase-* podem ser removidas manualmente se necessário.
  end
end
