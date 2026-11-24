class RamonBiPolicy < ApplicationPolicy
  # Quem VÊ o BI mora só aqui: a próxima fatia abre a visão a sócios liberados sem mexer em quem envia.
  def show? = @account_user.administrator?

  # Enviar nova versão fica sempre com administrador.
  def update? = @account_user.administrator?
end
