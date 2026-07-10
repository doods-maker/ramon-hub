# Evento entrante do Flowter (ADVBOX). Guarda o payload cru (o schema do
# HTTP Request do Flowter não é documentado — modo captura) e serve de chave
# de idempotência; o estado de domínio vive em Lead/LeadActivity/LeadTask.
class AdvboxEvent < ApplicationRecord
  belongs_to :account

  STATUSES = %w[received processed unmatched ignored error].freeze

  validates :event_key, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
end
