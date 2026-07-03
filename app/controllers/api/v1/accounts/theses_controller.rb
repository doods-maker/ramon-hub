class Api::V1::Accounts::ThesesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_thesis, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @theses = Current.account.theses
  end

  def show; end

  def create
    @thesis = Current.account.theses.new(permitted_params)
    @thesis.position = next_position
    @thesis.save!
    render :show
  end

  def update
    @thesis.update!(permitted_params)
    render :show
  end

  def destroy
    @thesis.destroy!
    head :ok
  end

  def reorder
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index do |id, i|
        Current.account.theses.find(id).update!(position: i)
      end
    end
    @theses = Current.account.theses
    render :index
  end

  private

  def fetch_thesis
    @thesis = Current.account.theses.find(params[:id])
  end

  def next_position
    (Current.account.theses.maximum(:position) || -1) + 1
  end

  def permitted_params
    params.permit(:name, :description, :area, :active)
  end
end
