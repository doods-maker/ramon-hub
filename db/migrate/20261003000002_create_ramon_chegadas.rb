# Equipe · chegada de cliente: Recepção avisa, destinatário responde (texto livre),
# sem resposta em 3 min escala de volta pra quem avisou.
class CreateRamonChegadas < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_chegadas do |t|
      t.bigint :account_id, null: false
      t.bigint :criado_por_id, null: false
      t.bigint :destinatario_id, null: false
      t.string :cliente_nome, null: false
      t.string :motivo
      t.bigint :advbox_customer_id
      t.bigint :advbox_post_id
      t.text :resposta
      t.datetime :respondido_em
      t.datetime :escalado_em
      t.timestamps
      t.index [:account_id, :created_at]
    end
  end
end
