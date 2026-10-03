# Extrato mensal da variável (playbook §13, item 6): o gestor vê todo mundo e
# lança a meta do mês; SDR/Closer veem só o próprio extrato (somente leitura).
class Api::V1::Accounts::RamonExtratoController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    pessoas = Ramon::ExtratoVariavel.new(account: Current.account, mes: mes).pessoas
    pessoas = pessoas.select { |p| p[:user][:id] == Current.user.id } unless Current.account_user.administrator?
    render json: { mes: mes.strftime('%Y-%m'), regras: Ramon::ExtratoVariavel::REGRAS, pessoas: pessoas }
  end

  def meta
    user = Current.account.users.find(params[:user_id])
    registro = MetaComercial.find_or_initialize_by(account: Current.account, user: user, mes: mes)
    registro.update!(papel: params[:papel], meta: params[:meta].to_i, rampa: ActiveModel::Type::Boolean.new.cast(params[:rampa]) || false)
    render json: registro.slice(:user_id, :papel, :meta, :rampa)
  end

  private

  # ?mes=AAAA-MM; padrão = mês corrente no fuso do escritório.
  def mes
    @mes ||= if params[:mes].to_s.match?(/\A\d{4}-\d{2}\z/)
               Date.parse("#{params[:mes]}-01")
             else
               Time.current.in_time_zone(Ramon::ExtratoVariavel::TIME_ZONE).to_date.beginning_of_month
             end
  end

  def check_authorization
    authorize(:ramon_extrato, :"#{action_name}?")
  end
end
