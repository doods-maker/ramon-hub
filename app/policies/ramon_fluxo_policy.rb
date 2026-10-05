# Automações em fluxo: só administradores montam, publicam, ensaiam e veem execuções.
class RamonFluxoPolicy < ApplicationPolicy
  def gerenciar?
    @account_user.administrator?
  end
end
