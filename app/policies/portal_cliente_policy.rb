class PortalClientePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show? = index?
  def create? = index?
  def update? = index?
  def convidar? = index?
  def assinatura? = index?
end
