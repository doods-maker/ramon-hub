# O chat interno do #303 (tabelas próprias) deu lugar à caixa Equipe do Chatwoot (ADR 0011).
# As tabelas estavam vazias em produção; if_exists porque o banco novo nunca as criou.
class DropRamonChat < ActiveRecord::Migration[7.1]
  def up
    drop_table :ramon_chat_mensagens, if_exists: true
    drop_table :ramon_chat_membros, if_exists: true
    drop_table :ramon_chat_canais, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
