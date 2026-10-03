class RamonChegadaPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def responder?
    index?
  end

  def create?
    @account_user.administrator? || Chegada.recepcao?(@account, @user)
  end

  def agenda?
    create?
  end
end
