class RamonEsteiraPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def done?
    show?
  end

  def snooze?
    show?
  end
end
