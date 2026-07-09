class Api::V1::Accounts::LinhaDaVidaController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    @contact = Current.account.contacts.find(params[:contact_id])
    @leads = Current.account.leads.where(contact_id: @contact.id)
                    .reorder(:id).includes(:lead_stage, :benefit_type, :thesis)
    @marcos = Ramon::MarcosEtarios.para(data_nascimento: @contact.data_nascimento, sexo: @contact.sexo)
  end

  private

  def check_authorization
    authorize(:linha_da_vida, :show?)
  end
end
