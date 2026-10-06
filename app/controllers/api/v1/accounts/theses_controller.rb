class Api::V1::Accounts::ThesesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_thesis, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @theses = Current.account.theses
  end

  def show; end

  def create
    @thesis = Current.account.theses.new(permitted_params.reverse_merge(Thesis::HONORARIO_PADRAO))
    @thesis.position = next_position
    @thesis.save!
    render :show
  end

  def update
    @thesis.update!(permitted_params)
    render :show
  end

  # Tese com leads não é excluída (o destroy anularia a tese desses leads):
  # o caminho é desativar, que a tira da escolha de tese dos leads novos.
  def destroy
    leads_count = @thesis.leads.count
    return render_tese_em_uso(leads_count) if leads_count.positive?

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

  def render_tese_em_uso(count)
    sujeito = count == 1 ? '1 lead usa' : "#{count} leads usam"
    render json: { error: "#{sujeito} esta tese — desative em vez de excluir", leads_count: count },
           status: :unprocessable_entity
  end

  def next_position
    (Current.account.theses.maximum(:position) || -1) + 1
  end

  def permitted_params
    params.permit(:name, :description, :area, :active, :honorario_percentual, :honorario_n_mensalidades)
  end
end
