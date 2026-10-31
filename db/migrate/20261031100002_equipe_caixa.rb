# Equipe · chat interno como caixa do Chatwoot (ADR 0011): a caixa é marcada por `equipe` e a não-lida é por
# pessoa (quem participa da conversa), no last_seen_at do participante.
class EquipeCaixa < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :equipe, :boolean, default: false, null: false
    add_column :conversation_participants, :last_seen_at, :datetime
  end
end
