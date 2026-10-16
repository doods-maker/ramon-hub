# Conta Google de cada usuário da Agenda no hub: tokens cifrados no model (encrypts), um registro por usuário.
# `status`: conectada | desconectada (refresh token revogado → o usuário precisa reconectar).
class CreateRamonGoogleAgendas < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_google_agendas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :email
      t.text :access_token
      t.text :refresh_token
      t.datetime :expira_em
      t.string :status, null: false, default: 'conectada'
      t.datetime :ultima_sincronizacao_em
      t.timestamps
    end
  end
end
