class LeadActivityPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end
end
