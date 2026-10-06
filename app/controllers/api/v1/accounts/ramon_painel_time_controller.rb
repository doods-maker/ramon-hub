# Painel do time (Resultados → Painel do time): KPIs do SDR/Closer com meta do
# plano. Gestor (admin) recebe o agregado do time e a lista por pessoa;
# SDR/Closer recebem só a própria linha — como no extrato da variável.
# ?papel=sdr|closer (padrão sdr) & ?periodo=hoje|semana|mes|mes_passado (padrão mes).
class Api::V1::Accounts::RamonPainelTimeController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    render json: Ramon::PainelTime.new(account: Current.account, papel: papel, periodo: periodo,
                                       user: Current.account_user.administrator? ? nil : Current.user).perform
  end

  private

  def papel
    params[:papel] == Ramon::Papeis::CLOSER ? Ramon::Papeis::CLOSER : Ramon::Papeis::SDR
  end

  def periodo
    Ramon::PainelTime::PERIODOS.include?(params[:periodo]) ? params[:periodo] : 'mes'
  end

  def check_authorization
    authorize(:ramon_painel_time, :show?)
  end
end
