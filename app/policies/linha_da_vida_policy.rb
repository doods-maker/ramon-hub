class LinhaDaVidaPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || @account_user.agent?
  end
end
