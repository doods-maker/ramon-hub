# Chat da equipe: participante vê e escreve; administrador lê qualquer canal
# (inclusive 1:1), mas só escreve onde participa.
class ChatCanalPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def direto?
    index?
  end

  def show?
    @account_user.administrator? || record.participante?(@user)
  end

  def enviar?
    record.participante?(@user)
  end

  def ler?
    enviar?
  end
end
