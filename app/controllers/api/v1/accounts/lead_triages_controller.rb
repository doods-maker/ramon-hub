class Api::V1::Accounts::LeadTriagesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead
  before_action :check_authorization

  def index
    @lead_triages = @lead.lead_triages.order(id: :desc).limit(10)
  end

  def create
    expire_orphan_triages
    agent = fetch_agent
    @lead_triage = @lead.lead_triages.create!(account: Current.account, triage_agent: agent)
    Leads::TriageJob.perform_later(@lead_triage.id)
    render :show
  end

  def kit
    @lead_triage = @lead.lead_triages.find(params[:id])
    return render_could_not_create_error('Triagem ainda não concluída') unless @lead_triage.status == 'done'

    @lead_triage.update!(kit_status: 'running')
    Leads::KitJob.perform_later(@lead_triage.id)
    render :show
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def fetch_agent
    return Current.account.triage_agents.active.find(params[:triage_agent_id]) if params[:triage_agent_id].present?

    Current.account.triage_agents.active.order(:id).first or
      raise ActiveRecord::RecordNotFound, 'no active triage agent'
  end

  # destrava o botão da UI quando um worker morre no meio (deploy/OOM):
  # triagens pending/running órfãs (sem atualização há 10min) viram error.
  def expire_orphan_triages
    @lead.lead_triages.where(status: %w[pending running])
         .where(updated_at: ...10.minutes.ago)
         .find_each do |triage|
      triage.update!(status: 'error', error_message: 'Triagem expirada (worker interrompido)')
    end
  end

  def check_authorization
    authorize(LeadTriage)
  end
end
