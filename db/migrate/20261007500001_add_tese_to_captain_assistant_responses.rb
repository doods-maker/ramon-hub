# FAQ por tese (I-FQ1): a tese que já está no nome do arquivo do seed
# (db/seeds/ramon/inteligencia/faq/<tese>.md) passa a ficar na FAQ — filtro e
# etiqueta na tela. Nula = sem tese (ex.: FAQ gerada de documento).
class AddTeseToCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistant_responses, :tese, :string
  end
end
