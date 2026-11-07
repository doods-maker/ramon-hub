# Quem assume a conversa em Documentos quando a IA passa para uma pessoa (spec Etapa Documentos §6): o SDR do lead se
# estiver online no hub; senão o closer online; senão o SDR (ou o closer) mesmo offline, porque alguém precisa ser dono;
# sem nenhum, nil (o aviso vai aos administradores: Ramon::AvisoDaIa.avisar).
# ponytail: online pelo status do Chatwoot; trocar por horário de trabalho se o status não for confiável na operação (spec §6).
module Ramon::Documentos::Responsavel
  module_function

  # @return [User, nil]
  def de(lead)
    pessoas = [lead.sdr, lead.closer].compact
    pessoas.find { |user| online?(lead.account, user) } || pessoas.first
  end

  def online?(account, user) = account.account_users.find_by(user_id: user.id)&.availability_status == 'online'
end
