# Usuário do ADVBOX ↔ usuário do hub, casados por e-mail (settings em cache de 24 h via Ramon::AdvboxCache).
module Ramon::AdvboxUsuarios
  module_function

  def usuario(account, advbox_user_id)
    email = emails[advbox_user_id]
    email && account.users.find_by('LOWER(users.email) = ?', email.downcase)
  end

  # ids do ADVBOX com o e-mail da pessoa (sem diferenciar maiúscula).
  def ids_de(user)
    emails.select { |_id, email| email.to_s.casecmp?(user.email) }.keys
  end

  def emails
    Ramon::AdvboxCache.buscar('ramon/advbox_users_email', expires_in: 24.hours) do
      Array(Ramon::AdvboxClient.settings['users']).to_h { |user| [user['id'], user['email']] }
    end.to_h
  end
end
