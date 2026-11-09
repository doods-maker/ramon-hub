class RamonExtratoPolicy < ApplicationPolicy
  # O controller filtra: agente vê só o próprio extrato.
  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def meta?
    @account_user.administrator?
  end

  def programas?
    @account_user.administrator?
  end

  def programa?
    @account_user.administrator?
  end
end
