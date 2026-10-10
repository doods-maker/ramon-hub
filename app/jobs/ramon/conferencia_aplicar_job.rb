# Grava no ADVBOX a etapa sugerida das linhas marcadas da Conferência de fases (clique do administrador).
class Ramon::ConferenciaAplicarJob < ApplicationJob
  queue_as :default

  def perform(account_id, user_id)
    Ramon::ConferenciaFases.new(Account.find(account_id)).aplicar!(User.find_by(id: user_id))
  end
end
