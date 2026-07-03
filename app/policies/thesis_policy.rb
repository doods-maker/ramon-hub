class ThesisPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create? = @account_user.administrator?
  def update? = @account_user.administrator?
  def destroy? = @account_user.administrator?
  def reorder? = @account_user.administrator?
end
