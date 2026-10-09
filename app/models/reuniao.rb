# Reunião presencial gravada na área "Reuniões" da Intranet: áudio no
# ActiveStorage (R2), transcrição do faster-whisper local e ata gerada por LLM.
class Reuniao < ApplicationRecord
  self.table_name = 'ramon_reunioes'

  STATUSES = %w[transcrevendo pronta erro].freeze

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :lead, optional: true
  has_one_attached :audio

  validates :status, inclusion: { in: STATUSES }

  scope :recentes, -> { order(created_at: :desc) }

  # FluxoExecucao#alvo_nome
  def nome_de_alvo = "Reunião gravada: #{titulo_exibicao}"

  # Hora do escritório (o servidor roda em UTC).
  def titulo_exibicao
    titulo.presence || "Reunião de #{created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}"
  end
end
