class RamonCalculosPolicy < ApplicationPolicy
  def advbox_customers?
    @account_user.administrator? || @account_user.agent?
  end

  def criar_caso?
    advbox_customers?
  end
end
