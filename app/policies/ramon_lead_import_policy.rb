class RamonLeadImportPolicy < ApplicationPolicy
  def create?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end
end
