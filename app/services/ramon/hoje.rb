# Tela "Hoje" (redesign v2, Onda 3): o que cada papel precisa fazer agora.
# O papel é decidido aqui, nunca pelo front.
class Ramon::Hoje
  pattr_initialize [:account!, :user!]

  def perform
    papel = Ramon::Papeis.papel_de(account, user)
    { papel: papel, data: Time.find_zone!(Chegada::ZONA).today.iso8601 }.merge(blocos(papel))
  end

  private

  def blocos(papel)
    case papel
    when 'gestor' then Ramon::Hoje::Gestor.new(account: account).perform
    when 'recepcao', 'advogada' then Ramon::Hoje::Escritorio.new(account: account, user: user, papel: papel).perform
    else Ramon::Hoje::Comercial.new(account: account, user: user, papel: papel).perform
    end
  end
end
