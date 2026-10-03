# Tela "Hoje" (redesign v2, Onda 3): o que cada papel precisa fazer agora.
# O papel é decidido aqui, nunca pelo front.
class Ramon::Hoje
  pattr_initialize [:account!, :user!]

  def perform
    papel = Ramon::Papeis.papel_de(account, user)
    { papel: papel, data: Time.find_zone!(Chegada::ZONA).today.iso8601 }.merge(blocos(papel))
  end

  private

  def blocos(_papel)
    {}
  end
end
