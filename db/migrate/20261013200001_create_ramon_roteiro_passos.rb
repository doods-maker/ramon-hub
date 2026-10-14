# Roteiro da tese (spec 2026-10-13 §3.1): passos de qualificação por tese; thesis_id nulo = passo comum da conta.
# palavras_chave e os padrões por caixa entram aqui (uma regeneração de schema só) e são usados na F3.
class CreateRamonRoteiroPassos < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :ramon_roteiro_passos do |t|
      t.bigint :account_id, null: false
      t.bigint :thesis_id
      t.integer :position, null: false, default: 0
      t.string :chave, null: false
      t.string :titulo, null: false
      t.text :orientacao
      t.string :tipo_resposta, null: false, default: 'texto'
      t.jsonb :opcoes, null: false, default: []
      t.string :calculadora
      t.jsonb :calculadora_campos, null: false, default: {}
      t.jsonb :saidas, null: false, default: []
      t.boolean :edited, null: false, default: false
      t.timestamps
    end
    add_index :ramon_roteiro_passos, :account_id
    add_index :ramon_roteiro_passos, %i[thesis_id chave], unique: true, where: 'thesis_id IS NOT NULL',
                                                          name: 'index_ramon_roteiro_passos_on_thesis_and_chave'
    add_index :ramon_roteiro_passos, %i[account_id chave], unique: true, where: 'thesis_id IS NULL',
                                                           name: 'index_ramon_roteiro_passos_comuns_on_chave'

    add_column :theses, :palavras_chave, :string, array: true, null: false, default: []
    add_column :inboxes, :ramon_thesis_id, :bigint
    add_column :inboxes, :ramon_copiloto_modo, :string
  end
  # rubocop:enable Metrics/MethodLength
end
