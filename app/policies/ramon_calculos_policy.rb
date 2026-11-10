class RamonCalculosPolicy < ApplicationPolicy
  # A busca devolve CPF, celular e e-mail da base inteira do ADVBOX: só o jurídico (decisão 10/11/2026).
  def advbox_customers?
    @account_user.administrator? || Ramon::Papeis.membro?(@account, @user, Ramon::Papeis::JURIDICO)
  end

  def criar_caso?
    @account_user.administrator? || @account_user.agent?
  end

  def rascunho?
    criar_caso?
  end
end
