class Api::V1::Accounts::LeadStagesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_stage, only: [:update, :destroy]

  def create
    authorize LeadStage
    @stage = Current.account.lead_stages.new(permitted_params)
    @stage.label = Ramon::StageSlug.label_for(@stage.name)
    @stage.position ||= next_position
    @stage.save!
    render :show
  end

  def update
    authorize @stage
    old_label = @stage.label
    @stage.assign_attributes(permitted_params)
    @stage.label = Ramon::StageSlug.label_for(@stage.name) if @stage.name_changed?
    ActiveRecord::Base.transaction do
      @stage.save!
      sync_labels(old_label)
    end
    render :show
  end

  def destroy
    authorize @stage
    return render_error('destino obrigatório') if params[:move_to_stage_id].blank?
    return render_error('não é possível remover a última etapa') if Current.account.lead_stages.count <= 1

    target = Current.account.lead_stages.find(params[:move_to_stage_id])
    ActiveRecord::Base.transaction do
      @stage.leads.find_each do |lead|
        lead.update!(lead_stage: target)
        Ramon::StageLabelSync.apply_to_conversation(lead)
      end
      deleted_label = @stage.label
      @stage.destroy!
      Current.account.labels.find_by(title: deleted_label)&.destroy
    end
    head :ok
  rescue ActiveRecord::RecordNotFound
    render_error('etapa destino inválida')
  end

  def reorder
    authorize LeadStage, :reorder?
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index do |id, i|
        Current.account.lead_stages.where(id: id).update_all(position: i)
      end
    end
    @stages = Current.account.lead_stages
    render :index
  end

  private

  def fetch_stage
    @stage = Current.account.lead_stages.find(params[:id])
  end

  def next_position
    (Current.account.lead_stages.maximum(:position) || -1) + 1
  end

  def sync_labels(old_label)
    if @stage.saved_change_to_label?
      Ramon::StageLabelSync.rename_label(Current.account, old_label, @stage.label, @stage.color)
    elsif @stage.saved_change_to_color?
      Ramon::StageLabelSync.recolor_label(Current.account, @stage.label, @stage.color)
    end
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def permitted_params
    params.permit(:name, :color, :is_won, :is_lost)
  end
end
