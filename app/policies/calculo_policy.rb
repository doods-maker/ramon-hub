class CalculoPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def reabrir?
    index?
  end

  def destroy?
    index?
  end
end
