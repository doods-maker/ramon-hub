class LeadTaskPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || @account_user.agent?
  end

  def complete?
    @account_user.administrator? || @account_user.agent?
  end

  def destroy?
    @account_user.administrator? || @account_user.agent?
  end
end
