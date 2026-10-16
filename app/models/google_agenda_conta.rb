# Conta Google do usuário para a Agenda no hub (tokens cifrados). Um registro por usuário.
class GoogleAgendaConta < ApplicationRecord
  self.table_name = 'ramon_google_agendas'

  if Chatwoot.encryption_configured?
    encrypts :access_token
    encrypts :refresh_token
  end

  belongs_to :user
  belongs_to :account

  validates :user_id, uniqueness: true

  scope :conectadas, -> { where(status: 'conectada') }

  def self.de(user)
    conectadas.find_by(user_id: user.id)
  end
end
