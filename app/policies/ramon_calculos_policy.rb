class RamonCalculosPolicy < ApplicationPolicy
  # A busca devolve CPF, celular e e-mail da base inteira do ADVBOX: só o jurídico (Cálculos; decisão 10/11/2026) e os
  # times das outras duas telas que usam esta mesma busca: "Chegou cliente" (recepção) e Portal de Clientes.
  QUEM_BUSCA_NO_ADVBOX = [Ramon::Papeis::JURIDICO, *PortalClientePolicy::EQUIPES_ACESSO].freeze

  def advbox_customers?
    @account_user.administrator? || @user.teams.exists?(account_id: @account.id, name: QUEM_BUSCA_NO_ADVBOX)
  end

  def criar_caso?
    @account_user.administrator? || @account_user.agent?
  end

  def rascunho?
    criar_caso?
  end
end
