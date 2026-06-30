class Api::V1::Accounts::LeadPrioritiesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_record, only: [:update, :destroy]

  def create
    authorize LeadPriority
    @record = Current.account.lead_priorities.new(permitted_params)
    @record.position = (Current.account.lead_priorities.maximum(:position) || -1) + 1
    @record.save!
    render :show
  end

  def update
    authorize @record
    @record.update!(permitted_params)
    render :show
  end

  def destroy
    authorize @record
    @record.destroy!
    head :ok
  end

  def reorder
    authorize LeadPriority, :reorder?
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index do |id, i|
        Current.account.lead_priorities.find(id).update!(position: i)
      end
    end
    @records = Current.account.lead_priorities
    render :index
  end

  private

  def fetch_record
    @record = Current.account.lead_priorities.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :weight)
  end
end
