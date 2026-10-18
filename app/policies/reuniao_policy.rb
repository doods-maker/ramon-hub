class ReuniaoPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def update?
    index?
  end

  # Apagar gravação/ata só admin ou quem gravou (ver e editar seguem abertos a todos — 28/07).
  def destroy?
    @account_user.administrator? || record.user_id == @user.id
  end

  def reprocessar?
    index?
  end
end
