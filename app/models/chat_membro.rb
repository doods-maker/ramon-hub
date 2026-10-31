# Participação no canal direto (Equipe · chat) e o lido_ate de cada pessoa.
class ChatMembro < ApplicationRecord
  self.table_name = 'ramon_chat_membros'

  belongs_to :canal, class_name: 'ChatCanal', inverse_of: :membros
  belongs_to :user
end
