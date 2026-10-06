class Api::V1::Accounts::LeadStagesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_stage, only: [:update, :destroy]

  def create
    authorize LeadStage
    @stage = Current.account.lead_stages.new(permitted_params)
    @stage.label = Ramon::StageSlug.unique_label_for(Current.account, @stage.name)
    @stage.position = next_position
    @stage.save!
    render :show
  end

  # Renomear muda só o nome exibido: o label (fase-*) é fixo desde a criação,
  # porque o código acha etapas por ele (quiz, agendamento, contrato) e as
  # conversas já carregam a label fase-* correspondente.
  def update
    authorize @stage
    ActiveRecord::Base.transaction do
      @stage.update!(permitted_params)
      recolor_label
    end
    render :show
  end

  def destroy
    authorize @stage
    error = destroy_error
    return render_error(error) if error

    enqueue_stage_merge(Current.account.lead_stages.find(params[:move_to_stage_id]))
    head :ok
  rescue ActiveRecord::RecordNotFound
    render_error('etapa destino inválida')
  end

  def reorder
    authorize LeadStage, :reorder?
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index do |id, i|
        Current.account.lead_stages.find(id).update!(position: i)
      end
    end
    @stages = Current.account.lead_stages
    render :index
  end

  private

  def fetch_stage
    @stage = Current.account.lead_stages.find(params[:id])
  end

  def destroy_error
    return 'etapa usada pelas automações (quiz, agendamento, contrato) — não pode ser removida' if @stage.automacao?
    return 'destino obrigatório' if params[:move_to_stage_id].blank?
    return 'destino não pode ser a própria etapa' if params[:move_to_stage_id].to_s == @stage.id.to_s

    'não é possível remover a última etapa' if Current.account.lead_stages.count <= 1
  end

  # Mover N leads é trabalho de fundo (com centenas, travava o request);
  # a etapa some do config na hora e os cards migram via broadcast.
  def enqueue_stage_merge(target)
    Ramon::StageMergeJob.perform_later(@stage.id, target.id, Current.user&.id)
  end

  def next_position
    (Current.account.lead_stages.maximum(:position) || -1) + 1
  end

  def recolor_label
    Ramon::StageLabelSync.recolor_label(Current.account, @stage.label, @stage.color) if @stage.saved_change_to_color?
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def permitted_params
    params.permit(:name, :color, :is_won, :is_lost, :probability, :stalled_after_days, :nome_cliente)
  end
end
