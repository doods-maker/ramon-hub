class Api::V1::Accounts::ThesisItemsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_thesis
  before_action :fetch_item, only: [:update, :destroy]

  def create
    authorize ThesisItem
    @item = @thesis.thesis_items.new(permitted_params)
    @item.position = next_position
    @item.save!
    render :show
  end

  def update
    authorize @item
    @item.update!(permitted_params)
    render :show
  end

  def destroy
    authorize @item
    @item.destroy!
    head :ok
  end

  def reorder
    authorize ThesisItem, :reorder?
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index do |id, i|
        @thesis.thesis_items.find(id).update!(position: i)
      end
    end
    @items = @thesis.thesis_items
    render :index
  end

  private

  def fetch_thesis
    @thesis = Current.account.theses.find(params[:thesis_id])
  end

  def fetch_item
    @item = @thesis.thesis_items.find(params[:id])
  end

  def next_position
    (@thesis.thesis_items.maximum(:position) || -1) + 1
  end

  def permitted_params
    params.permit(:section, :title, :content)
  end
end
