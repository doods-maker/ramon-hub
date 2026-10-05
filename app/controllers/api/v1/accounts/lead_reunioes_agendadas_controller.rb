# "+ Tarefa" → Reunião no painel do lead: o mesmo efeito da reunião marcada
# pelo Cal.com (Ramon::ReuniaoAgendamento). Nada é enviado ao cliente — a
# confirmação nasce como nota RASCUNHO.
class Api::V1::Accounts::LeadReunioesAgendadasController < Api::V1::Accounts::BaseController
  def create
    @lead = Current.account.leads.find(params[:lead_id])
    authorize(@lead, :update?)
    return render json: { error: 'STARTS_AT_INVALIDO' }, status: :unprocessable_entity if starts_at.blank?

    title = params[:title].to_s.strip.presence || 'Reunião'
    Ramon::ReuniaoAgendamento.call(lead: @lead, starts_at: starts_at, title: title, user: Current.user)
    render 'api/v1/accounts/leads/show', format: :json
  end

  private

  def starts_at
    @starts_at ||= Time.zone.parse(params[:starts_at].to_s)
  rescue ArgumentError
    nil
  end
end
