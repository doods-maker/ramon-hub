class RamonRelatorioPolicy < ApplicationPolicy
  def show? = @account_user.administrator?
end
