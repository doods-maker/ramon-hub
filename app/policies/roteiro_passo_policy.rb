# Passos do roteiro da tese (F2): todos leem; só admin cadastra (mesma regra das teses).
class RoteiroPassoPolicy < ApplicationPolicy
  def index? = @account_user.administrator? || @account_user.agent?
  def create? = @account_user.administrator?
  def update? = @account_user.administrator?
  def destroy? = @account_user.administrator?
  def reorder? = @account_user.administrator?
end
