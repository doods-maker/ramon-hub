# Registro de cada ação automática do funil (IA/regras): o ponto único Ramon::FunilAutomatico grava aqui antes de aplicar.
# `ensaio` = só registrou; `desfazer` = o que o botão "desfazer" precisa; `desfeita_*` = quem reverteu e quando.
class CreateRamonFunilAcoes < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_funil_acoes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.string :peca, null: false
      t.string :acao, null: false
      t.string :motivo, limit: 250
      t.string :alvo
      t.jsonb :desfazer, null: false, default: {}
      t.boolean :ensaio, null: false, default: false
      t.datetime :desfeita_em
      t.references :desfeita_por, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end
    add_index :ramon_funil_acoes, [:account_id, :created_at]
  end
end
