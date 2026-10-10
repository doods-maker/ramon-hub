# Conferência de fases: a equipe vê e marca; só o administrador aplica no ADVBOX (o clique dele é o "aprovado").
class RamonConferenciaFasePolicy < ApplicationPolicy
  def index? = @account_user.administrator? || @account_user.agent?
  def update? = index?
  def aplicar? = @account_user.administrator?
end
