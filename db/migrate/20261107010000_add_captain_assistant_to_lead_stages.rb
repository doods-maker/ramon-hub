# Etapa Documentos (spec §2): assistente próprio da etapa. Sem FK: assistente apagado = a etapa volta ao da caixa.
class AddCaptainAssistantToLeadStages < ActiveRecord::Migration[7.1]
  def change
    add_reference :lead_stages, :captain_assistant, null: true, index: true, foreign_key: false
  end
end
