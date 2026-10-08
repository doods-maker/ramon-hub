# Skills (Inteligência A5): fala de exemplo para "Testar esta skill" (I-SK6) e papéis (nomes de time)
# que mais usam a skill — o Testar mostra primeiro as do seu papel (I-X5).
class AddExemploEPapeisToCaptainScenarios < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_scenarios, :exemplo, :text
    add_column :captain_scenarios, :papeis, :jsonb, default: [], null: false
  end
end
