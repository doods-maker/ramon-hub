class CopilotSuggestionPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def apply?
    @account_user.administrator? || @account_user.agent?
  end

  def dismiss?
    @account_user.administrator? || @account_user.agent?
  end

  def apply_all?
    @account_user.administrator? || @account_user.agent?
  end
end
