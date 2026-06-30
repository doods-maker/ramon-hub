class LeadPriorityPolicy < ApplicationPolicy
  def create? = @account_user.administrator?
  def update? = @account_user.administrator?
  def destroy? = @account_user.administrator?
  def reorder? = @account_user.administrator?
end
