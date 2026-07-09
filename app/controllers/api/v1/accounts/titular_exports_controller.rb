# Endpoint LGPD art. 18: dump JSON completo do titular (Ramon::TitularExport).
class Api::V1::Accounts::TitularExportsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    contact = Current.account.contacts.find(params[:contact_id])
    render json: Ramon::TitularExport.new(contact).payload
  end

  private

  def check_authorization
    authorize(:titular_export, :show?)
  end
end
