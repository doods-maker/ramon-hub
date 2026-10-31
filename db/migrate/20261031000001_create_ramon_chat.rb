# Equipe · chat interno (Fatia 2): canais Geral, por setor (time) e 1:1,
# isolados das conversas de cliente. `chave` garante um geral por conta, um
# setor por time e um direto por par.
class CreateRamonChat < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :ramon_chat_canais do |t|
      t.bigint :account_id, null: false
      t.string :tipo, null: false
      t.string :chave, null: false
      t.bigint :team_id
      t.timestamps
      t.index [:account_id, :chave], unique: true
    end

    create_table :ramon_chat_membros do |t|
      t.bigint :canal_id, null: false
      t.bigint :user_id, null: false
      t.datetime :lido_ate
      t.timestamps
      t.index [:canal_id, :user_id], unique: true
      t.index :user_id
    end

    create_table :ramon_chat_mensagens do |t|
      t.bigint :canal_id, null: false
      t.bigint :autor_id, null: false
      t.text :conteudo, null: false
      t.timestamps
      t.index [:canal_id, :id]
    end
  end
end
