# Mensagem do chat da equipe (só texto). Chega ao vivo para os membros do canal
# e para os administradores (que leem tudo).
class ChatMensagem < ApplicationRecord
  self.table_name = 'ramon_chat_mensagens'

  belongs_to :canal, class_name: 'ChatCanal', inverse_of: :mensagens
  belongs_to :autor, class_name: 'User'

  validates :conteudo, presence: true, length: { maximum: 5000 }

  after_create_commit :transmitir

  def push_event_data
    {
      id: id, canal_id: canal_id, account_id: canal.account_id, conteudo: conteudo,
      autor: { id: autor_id, name: autor.name }, created_at: created_at.iso8601
    }
  end

  private

  def transmitir
    tokens = User.where(id: canal.membro_ids | Ramon::Papeis.gestor_ids(canal.account)).pluck(:pubsub_token)
    ActionCableBroadcastJob.perform_later(tokens, 'ramon.chat.message', push_event_data)
  end
end
