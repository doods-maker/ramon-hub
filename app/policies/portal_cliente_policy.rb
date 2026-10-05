# Painel do cliente no hub. Ver e mandar documento pra assinatura: todo agente.
# Senha nova (de quem já tem acesso), suspender e reativar: admin ou quem atende o cliente no balcão
# (times Recepção e Controladoria). Excluir: só admin.
class PortalClientePolicy < ApplicationPolicy
  EQUIPES_ACESSO = [Chegada::RECEPCAO, 'controladoria'].freeze

  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show? = index?
  def create? = index?
  def update? = index?
  def assinatura? = index?
  def convidar? = index?
  def nova_senha? = gerir_acesso?
  def suspender? = gerir_acesso?
  def reativar? = gerir_acesso?
  def destroy? = @account_user.administrator?

  def gerir_acesso?
    @account_user.administrator? || EQUIPES_ACESSO.any? { |nome| @account.teams.find_by(name: nome)&.members&.exists?(@user.id) }
  end
end
