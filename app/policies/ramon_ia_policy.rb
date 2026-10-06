# Uso e custo da IA (Inteligência): números, provedor/modelo por função e teto de gasto — só administrador.
class RamonIaPolicy < ApplicationPolicy
  def gerenciar?
    @account_user.administrator?
  end
end
