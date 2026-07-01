class Api::V1::Accounts::LeadsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead, except: [:index, :create, :for_conversation]
  before_action :check_authorization

  def index
    @leads = policy_scope(Current.account.leads)
  end

  def show; end

  def create
    @lead = Current.account.leads.create!(permitted_params)
  end

  def update
    @lead.update!(permitted_params)
  end

  def destroy
    @lead.destroy!
    head :ok
  end

  def for_conversation
    conversation = Current.account.conversations.find(params[:conversation_id])
    @lead = find_or_create_lead_for(conversation)
    authorize(@lead, :show?)
  end

  private

  def find_or_create_lead_for(conversation)
    lead = Current.account.leads.find_by(conversation_id: conversation.id)
    return lead if lead

    lead = find_lead_for_contact(conversation)
    return lead if lead

    create_lead_for(conversation)
  end

  def find_lead_for_contact(conversation)
    return if conversation.contact_id.blank?

    lead = Current.account.leads.find_by(contact_id: conversation.contact_id)
    return if lead.blank?

    lead.update!(conversation_id: conversation.id) if lead.conversation_id != conversation.id
    lead
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end

  def create_lead_for(conversation)
    Current.account.leads.create!(
      conversation: conversation,
      contact: conversation.contact,
      lead_stage: default_lead_stage,
      name: lead_name_for(conversation)
    )
  end

  def default_lead_stage
    Current.account.lead_stages.order(:position).first
  end

  def lead_name_for(conversation)
    contact = conversation.contact
    contact&.name.presence || contact&.phone_number.presence || contact&.identifier.presence || "Lead ##{conversation.display_id}"
  end

  def permitted_params
    params.permit(:name, :lead_stage_id, :benefit_type_id, :lead_priority_id,
                  :contact_id, :conversation_id, :sdr_id, :closer_id,
                  :position, :lost_reason, :value, :source, :notes)
  end
end
