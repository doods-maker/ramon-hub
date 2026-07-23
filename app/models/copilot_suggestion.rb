# Sugestão do copiloto noturno (mock 4b): a IA trabalha de madrugada, o humano
# aprova de manhã. NADA é enviado ao cliente — aplicar um rascunho vira NOTA
# RASCUNHO no painel do lead; quem envia é o Eduardo.
class CopilotSuggestion < ApplicationRecord
  KINDS = %w[draft move_stage alert].freeze
  STATUSES = %w[pending applied dismissed].freeze

  belongs_to :account
  belongs_to :lead

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }

  # Aplica a sugestão. Retorna false quando move_stage não resolve a etapa
  # sugerida pelo nome (fallback = não aplica; olho humano decide).
  def apply!(user: nil)
    # Idempotência: aplicar de novo (clique duplo / apply_all repetido) não
    # duplica nota nem re-move etapa.
    return false unless status == 'pending'

    case kind
    when 'draft'
      lead.lead_notes.create!(account: account, user: user, body: draft_note_body)
    when 'move_stage'
      # A LLM nunca marca ganho/perdido: só etapa aberta resolve por nome.
      stage = account.lead_stages.where(is_won: false, is_lost: false).find_by(name: payload['etapa_sugerida'])
      return false if stage.blank?

      lead.update!(lead_stage_id: stage.id)
    end
    update!(status: 'applied')
    true
  end

  private

  # mesmo prefixo do FollowUpDraftService: a nota nasce e morre RASCUNHO
  def draft_note_body
    "RASCUNHO (revisar antes de enviar) — copiloto noturno:\n#{payload['texto']}".truncate(1000)
  end
end
