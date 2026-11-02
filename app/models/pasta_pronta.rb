# Pasta do Drive que a esteira deixou pronta para revisar (marcador _pasta-pronta.json).
# Some quando a petição da pasta passa a existir ou o marcador sai do Drive (Ramon::PastasProntasJob).
class PastaPronta < ApplicationRecord
  self.table_name = 'ramon_pastas_prontas'

  belongs_to :account
  belongs_to :responsavel, class_name: 'User', optional: true
  # destroy (não delete): o sino do item some junto e o after_destroy_commit da notificação avisa a tela
  has_many :notifications, as: :primary_actor, dependent: :destroy

  validates :drive_pasta_id, presence: true, uniqueness: { scope: :account_id }

  # Notification chama no ator; o título é dado interno (nunca vai ao push público).
  def push_event_data
    { id: id, titulo: titulo }
  end

  def as_json_hub
    { id: id, drive_pasta_id: drive_pasta_id, titulo: titulo, responsavel: responsavel && { id: responsavel.id, name: responsavel.name } }
  end
end
