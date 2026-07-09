# Export de dados do titular (LGPD) — só administrador, como o delete de contato.
class TitularExportPolicy < ApplicationPolicy
  def show?
    @account_user.administrator?
  end
end
