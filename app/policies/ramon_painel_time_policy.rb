class RamonPainelTimePolicy < ApplicationPolicy
  # O controller filtra: agente vê só a própria linha, sem o agregado do time.
  def show?
    @account_user.administrator? || @account_user.agent?
  end
end
