# Casos de teste da IA: só administrador cria, edita e roda.
class Captain::IaCasoPolicy < ApplicationPolicy
  def gerenciar?
    @account_user.administrator?
  end
end
