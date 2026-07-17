class Api::V1::Accounts::LeadsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead, except: [:index, :create, :for_conversation]
  before_action :check_authorization

  def index
    @leads = filtered_leads
  end

  def show; end

  def create
    existing = duplicate_open_lead
    if existing
      render json: { error: 'DUPLICATE_LEAD', existing: existing.push_event_data }, status: :conflict
      return
    end

    @lead = Current.account.leads.create!(permitted_params)
  end

  def update
    ensure_lost_reason!
    return if performed?

    @lead.update!(permitted_params)
  end

  def destroy
    @lead.destroy!
    head :ok
  end

  def for_conversation
    # o front manda o id do objeto de conversa da SPA, que é o display_id (por conta)
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
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

    lead = Current.account.leads.open.find_by(contact_id: conversation.contact_id)
    return if lead.blank?

    lead.update!(conversation_id: conversation.id) if lead.conversation_id != conversation.id
    lead
  end

  # Dedup por telefone na criação manual: o front resolve o contato pelo
  # telefone antes do create, então mesmo telefone == mesmo contact_id.
  # `force` presente = usuário confirmou "criar mesmo assim" após o 409.
  def duplicate_open_lead
    return if params[:force].present? || permitted_params[:contact_id].blank?

    Current.account.leads.open.find_by(contact_id: permitted_params[:contact_id])
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end

  def filtered_leads
    leads = apply_equality_filters(policy_scope(Current.account.leads))
    leads = leads.where('sdr_id = :a OR closer_id = :a', a: params[:agent_id]) if params[:agent_id].present?
    leads = apply_cadence_filters(apply_period_filters(leads))
    leads = search_leads(leads, params[:q]) if params[:q].present?
    leads
  end

  def apply_equality_filters(leads)
    %i[benefit_type_id lead_priority_id lead_stage_id source channel contact_id].each do |key|
      leads = leads.where(key => params[key]) if params[key].present?
    end
    leads
  end

  def apply_period_filters(leads)
    leads = leads.where(created_at: Date.parse(params[:created_after]).beginning_of_day..) if params[:created_after].present?
    leads = leads.where(created_at: ..Date.parse(params[:created_before]).end_of_day) if params[:created_before].present?
    leads
  end

  def apply_cadence_filters(leads)
    if params[:stalled].present?
      leads = leads.joins(:lead_stage).where.not(lead_stages: { stalled_after_days: nil })
                   .where("leads.stage_entered_at < NOW() - (lead_stages.stalled_after_days || ' days')::interval")
    end
    leads = leads.where.not(id: Current.account.lead_tasks.open_tasks.select(:lead_id)) if params[:no_open_task].present?
    leads
  end

  def ensure_lost_reason!
    target_stage_id = permitted_params[:lead_stage_id]
    return if target_stage_id.blank?

    stage = Current.account.lead_stages.find_by(id: target_stage_id)
    return unless stage&.is_lost
    return if permitted_params[:lost_reason].presence || @lead.lost_reason.presence

    render json: { error: 'LOST_REASON_REQUIRED' }, status: :unprocessable_entity
  end

  def search_leads(leads, query)
    like = "%#{query}%"
    leads.left_joins(:contact)
         .where('leads.name ILIKE :q OR contacts.name ILIKE :q OR contacts.phone_number ILIKE :q', q: like)
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
    params.permit(:name, :lead_stage_id, :benefit_type_id, :lead_priority_id, :thesis_id,
                  :contact_id, :conversation_id, :sdr_id, :closer_id,
                  :position, :lost_reason, :value, :source, :channel, :dcb_em, :benefit_monthly_value,
                  custom_attributes: {})
  end
end
