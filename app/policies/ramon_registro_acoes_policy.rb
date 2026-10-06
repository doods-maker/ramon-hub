# Registro de ações (audit log): só o gestor (administrador) vê a trilha.
class RamonRegistroAcoesPolicy < ApplicationPolicy
  def index? = @account_user.administrator?
end
