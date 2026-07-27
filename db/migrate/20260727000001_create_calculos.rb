class CreateCalculos < ActiveRecord::Migration[7.1]
  def change
    create_table :calculos do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :tipo, null: false
      t.string :segurado_nome
      t.string :segurado_cpf
      t.date :der
      # snapshot = tudo que faz o cálculo voltar ao estado exato (params do
      # formulário + CNIS já processado). O PDF em si nunca entra aqui.
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :calculos, [:account_id, :created_at]
    add_index :calculos, [:account_id, :segurado_nome]
  end
end
