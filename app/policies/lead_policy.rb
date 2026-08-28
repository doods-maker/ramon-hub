class LeadPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def for_conversation?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || @account_user.agent?
  end

  def portal_link?
    @account_user.administrator? || @account_user.agent?
  end

  def follow_up_draft?
    @account_user.administrator? || @account_user.agent?
  end

  def encaminhar_comercial?
    @account_user.administrator? || @account_user.agent?
  end

  def destroy?
    @account_user.administrator?
  end
end
