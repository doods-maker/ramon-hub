class CalculoPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def reabrir?
    index?
  end

  def vincular?
    index?
  end

  # Histórico é de quem calculou: só ele (ou o admin) apaga.
  def destroy?
    @account_user.administrator? || (index? && @record.user_id.present? && @record.user_id == @user.id)
  end
end
