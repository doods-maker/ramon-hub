class ReuniaoPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def destroy?
    index?
  end

  def reprocessar?
    index?
  end
end
