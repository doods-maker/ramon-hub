# FAQ "usada X vezes" (Inteligência A5 — I-FQ6): quantas vezes a ferramenta faq_lookup devolveu a FAQ no
# atendimento de verdade, e quando foi a última.
class AddUsoToCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistant_responses, :usos, :integer, default: 0, null: false
    add_column :captain_assistant_responses, :usada_em, :datetime
  end
end
