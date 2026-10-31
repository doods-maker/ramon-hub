# Equipe · chat interno como caixa do Chatwoot (ADR 0011). A caixa Equipe (Channel::Api sem webhook, inboxes.equipe)
# tem a conversa Geral (todos), uma por time (membros do time) e as 1:1, abertas sob demanda. Quem participa da conversa
# vê, responde e é avisado; administrador vê tudo. Cada conversa tem um contato sintético (additional_attributes.equipe)
# achado pelo source_id do contact_inbox: equipe-geral, equipe-time-<id>, equipe-1a1-<menor id>-<maior id>.
module Ramon::Equipe
  module_function

  # Consultas frescas (sem as associações do account): no commit de um AccountUser/TeamMember o account.users/teams
  # carregado antes no mesmo request ainda não tem a pessoa nova.
  def caixa(account)
    Inbox.find_by(account_id: account.id, equipe: true) if account
  end

  # Deploy/seed: criar: true. Os commits de TeamMember/AccountUser chamam sem criar — só acertam onde a caixa existe.
  def sincronizar(account, criar: false)
    inbox = caixa(account) || (criar && criar_caixa(account))
    return unless inbox

    conversa(inbox, 'geral', 'Geral', AccountUser.where(account_id: account.id).pluck(:user_id))
    canais_de_time(inbox, Team.where(account_id: account.id).to_a)
    inbox
  end

  # Um canal por time (membros do time); canal de time apagado fica sem ninguém.
  def canais_de_time(inbox, times)
    times.each { |team| conversa(inbox, "time-#{team.id}", "Setor #{team.name}", TeamMember.where(team_id: team.id).pluck(:user_id)) }
    apagados = inbox.contact_inboxes.where('source_id LIKE ?', 'equipe-time-%').where.not(source_id: times.map { |t| "equipe-time-#{t.id}" })
    apagados.each { |contact_inbox| contact_inbox.conversations.each { |c| participantes(c, []) } }
  end

  def conversa_1a1(account, user, outro)
    a, b = [user, outro].sort_by(&:id)
    conversa(caixa(account), "1a1-#{a.id}-#{b.id}", "#{a.available_name} e #{b.available_name}", [a.id, b.id])
  end

  # Não-lida por pessoa: mensagem de colega depois da última leitura de quem participa. Quem não participa (admin
  # olhando conversa alheia) não tem não-lida.
  def nao_lidas(conversation, user)
    participante = user && conversation.conversation_participants.find_by(user_id: user.id)
    return 0 unless participante

    mensagens = conversation.messages.where(sender_type: 'User').where.not(sender_id: user.id)
    mensagens = mensagens.where('messages.created_at > ?', participante.last_seen_at) if participante.last_seen_at
    mensagens.count
  end

  # ponytail: 1 contagem por conversa de que participa (dezenas); vira um SQL só se a equipe crescer muito.
  def total_nao_lidas(account, user)
    inbox = caixa(account)
    return 0 unless inbox

    inbox.conversations.where(id: user.conversation_participants.select(:conversation_id)).sum { |c| nao_lidas(c, user) }
  end

  def marcar_lida(conversation, user)
    conversation.conversation_participants.find_by(user_id: user.id)&.update!(last_seen_at: Time.current)
  end

  # Hub surdo (AsyncDispatcher): o evento é da caixa Equipe?
  def evento?(data)
    return data[:contact].additional_attributes.to_h['equipe'].present? if data[:contact].is_a?(Contact)

    inbox = data[:inbox] || (data[:conversation] || data[:message]&.conversation)&.inbox
    inbox.is_a?(Inbox) && inbox.equipe?
  end

  def criar_caixa(account)
    Inbox.create!(account_id: account.id, name: 'Equipe', channel: Channel::Api.create!(account_id: account.id), equipe: true,
                  enable_auto_assignment: false, enable_email_collect: false)
  end

  # Conversa sempre aberta: some da lista se alguém resolver; a próxima sincronização (ou o 1:1 de novo) reabre.
  # Conversa nova: o conversation.created saiu antes dos participantes existirem — o updated leva a eles ao vivo.
  def conversa(inbox, chave, nome, user_ids)
    contact_inbox = inbox.contact_inboxes.find_by(source_id: "equipe-#{chave}") || criar_contato(inbox, chave, nome)
    conversation = contact_inbox.conversations.first
    nova = conversation.nil?
    conversation ||= Conversation.create!(account_id: inbox.account_id, inbox: inbox, contact_id: contact_inbox.contact_id,
                                          contact_inbox: contact_inbox)
    conversation.open! unless conversation.open?
    participantes(conversation, user_ids)
    conversation.dispatch_conversation_updated_event if nova
    conversation
  end

  def criar_contato(inbox, chave, nome)
    contact = inbox.account.contacts.create!(name: nome, additional_attributes: { 'equipe' => true })
    ContactInbox.create!(contact: contact, inbox: inbox, source_id: "equipe-#{chave}")
  end

  def participantes(conversation, user_ids)
    atuais = conversation.conversation_participants.pluck(:user_id)
    conversation.conversation_participants.where(user_id: atuais - user_ids).destroy_all
    (user_ids - atuais).each { |user_id| conversation.conversation_participants.create!(user_id: user_id) }
  end
end
