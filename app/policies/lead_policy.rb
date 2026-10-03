class LeadPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def for_conversation?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || @account_user.agent?
  end

  def portal_link?
    @account_user.administrator? || @account_user.agent?
  end

  def follow_up_draft?
    @account_user.administrator? || @account_user.agent?
  end

  def encaminhar_comercial?
    @account_user.administrator? || @account_user.agent?
  end

  def destroy?
    @account_user.administrator?
  end

  # Reunião qualificada é base do prêmio do SDR (regulamento §2): quem marca é o
  # Closer do lead (ou alguém do time closer, se o lead ainda não tem) ou o gestor.
  def reuniao?
    return true if @account_user.administrator?
    return record.closer_id == @user.id if record.closer_id.present?

    Ramon::Papeis.membro?(@account, @user, Ramon::Papeis::CLOSER)
  end
end
