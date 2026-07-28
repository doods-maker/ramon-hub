class CreateRamonReunioes < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_reunioes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :titulo
      t.integer :duracao_segundos
      t.string :status, null: false, default: 'transcrevendo'
      t.string :erro
      t.text :transcricao
      t.text :ata
      t.timestamps
    end
    add_index :ramon_reunioes, [:account_id, :created_at]
  end
end
