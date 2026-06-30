class Api::V1::Accounts::BenefitTypesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_record, only: [:update, :destroy]

  def create
    authorize BenefitType
    @record = Current.account.benefit_types.new(permitted_params)
    @record.position = (Current.account.benefit_types.maximum(:position) || -1) + 1
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
    authorize BenefitType, :reorder?
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index do |id, i|
        Current.account.benefit_types.find(id).update!(position: i)
      end
    end
    @records = Current.account.benefit_types
    render :index
  end

  private

  def fetch_record
    @record = Current.account.benefit_types.find(params[:id])
  end

  def permitted_params
    params.permit(:name)
  end
end
