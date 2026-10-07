# Skills (I-SK4/I-SK5): editada na tela = a carga do seed não sobrescreve, não
# religa e não desliga; seed_titulo = o título do assistentes.yml que criou a
# skill (renomear na tela não faz o seed criar outra). As existentes nasceram
# do seed: seed_titulo = título atual.
class AddEdicaoToCaptainScenarios < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_scenarios, :edited, :boolean, default: false, null: false
    add_column :captain_scenarios, :seed_titulo, :string
    reversible { |dir| dir.up { execute('UPDATE captain_scenarios SET seed_titulo = title') } }
  end
end
