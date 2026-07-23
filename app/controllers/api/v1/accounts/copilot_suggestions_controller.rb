class Api::V1::Accounts::CopilotSuggestionsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :fetch_suggestion, only: [:apply, :dismiss]

  def index
    @copilot_suggestions = pending_scope.includes(:lead)
    # "revisou N leads": o universo que o job noturno varre (leads parados)
    @reviewed_count = Ramon::LeadRadar.stalled_leads(Current.account).count
  end

  def apply
    return if @copilot_suggestion.apply!(user: Current.user)

    # etapa sugerida por nome não resolveu = não aplica; olho humano decide
    render_could_not_create_error('Etapa sugerida não encontrada no funil — mova manualmente')
  end

  def dismiss
    @copilot_suggestion.update!(status: 'dismissed')
    render :apply
  end

  # move_stage NÃO entra no apply_all: mudança de funil em massa exige olho
  # humano, cartão a cartão. Só draft (vira nota RASCUNHO) e alert (só marca).
  def apply_all
    @copilot_suggestions = pending_scope.where(kind: %w[draft alert]).includes(:lead).to_a
    @copilot_suggestions.each { |suggestion| suggestion.apply!(user: Current.user) }
    render :index
  end

  private

  def pending_scope
    Current.account.copilot_suggestions.pending.order(:id)
  end

  def fetch_suggestion
    @copilot_suggestion = Current.account.copilot_suggestions.find(params[:id])
  end

  def check_authorization
    authorize(CopilotSuggestion)
  end
end
