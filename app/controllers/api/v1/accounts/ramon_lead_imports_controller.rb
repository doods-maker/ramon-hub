class Api::V1::Accounts::RamonLeadImportsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def create
    return render json: { error: 'import_file ausente' }, status: :unprocessable_entity if params[:import_file].blank?

    import = Current.account.data_imports.new(data_type: 'leads')
    import.import_file.attach(params[:import_file])
    import.save!
    render json: { id: import.id, status: import.status }
  end

  def show
    import = Current.account.data_imports.where(data_type: 'leads').find(params[:id])
    render json: import.slice(:id, :status, :total_records, :processed_records)
  end

  private

  def check_authorization
    authorize(:ramon_lead_import, "#{action_name}?".to_sym)
  end
end
