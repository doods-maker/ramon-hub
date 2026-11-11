class RamonCalculosPolicy < ApplicationPolicy
  # A busca devolve CPF, celular e e-mail da base inteira do ADVBOX: só quem tem time de trabalho com cliente (decisão
  # 10/11/2026) — jurídico (Cálculos), recepção ("Chegou cliente"), controladoria (Portal de Clientes) e o comercial
  # (conferir se o lead já tem cadastro). Agente sem nenhum desses times não busca.
  QUEM_BUSCA_NO_ADVBOX = [Ramon::Papeis::JURIDICO, *LeadPolicy::EQUIPES_VISAO_TOTAL].freeze

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
