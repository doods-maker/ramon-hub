class AddKitSystemPromptToTriageAgents < ActiveRecord::Migration[7.1]
  def up
    add_column :triage_agents, :kit_system_prompt, :text
    TriageAgent.reset_column_information
    TriageAgent.where(kit_system_prompt: nil)
               .update_all(kit_system_prompt: Leads::KitService::KIT_SYSTEM_PROMPT_DEFAULT) # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    remove_column :triage_agents, :kit_system_prompt
  end
end
