# Equipe · chat interno como caixa do Chatwoot (ADR 0011). A caixa Equipe (Channel::Api sem webhook, inboxes.equipe)
# tem a conversa Geral (todos), uma por time (membros do time) e as 1:1, abertas sob demanda. Quem participa da conversa
# vê, responde e é avisado; administrador vê tudo. Cada conversa tem um contato sintético (additional_attributes.equipe)
# achado pelo source_id do contact_inbox: equipe-geral, equipe-time-<id>, equipe-1a1-<menor id>-<maior id>.
module Ramon::Equipe # rubocop:disable Metrics/ModuleLength
  EMOJIS_REACAO = %w[👍 ❤️ 😂 😮 😢 🙏].freeze

  # O que o HTTP aceita numa conversa da Equipe, por controller; o resto dá 403, inclusive para admin (ADR 0011).
  # Quem vê e quem escreve seguem na ConversationPolicy e em pode_escrever?/pode_apagar?. Sincronizar não passa por aqui.
  # labels#index: a tela busca ao abrir a conversa (ConversationBox). A reação e a lista de vistos ficam em RamonEquipeController.
  HTTP_PERMITIDO = {
    'api/v1/accounts/conversations' => %w[show update_last_seen toggle_typing_status attachments],
    'api/v1/accounts/conversations/messages' => %w[index create destroy retry],
    'api/v1/accounts/conversations/participants' => %w[show],
    'api/v1/accounts/conversations/labels' => %w[index]
  }.freeze

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

    conversa(inbox, 'geral', 'Geral', usuarios(account))
    canais_de_time(inbox, Team.where(account_id: account.id).to_a)
    inbox
  end

  def usuarios(account) = AccountUser.where(account_id: account.id).pluck(:user_id)

  # Um canal por time (membros do time que ainda são da conta — quem sai da conta só some do time depois, num job);
  # canal de time apagado fica sem ninguém.
  def canais_de_time(inbox, times)
    times.each do |team|
      membros = TeamMember.where(team_id: team.id, user_id: usuarios(inbox.account)).pluck(:user_id)
      conversa(inbox, "time-#{team.id}", "Setor #{team.name}", membros)
    end
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
    mensagens_nao_lidas(conversation, user)&.count || 0
  end

  # Há mensagem não lida que marca a pessoa (@ nela ou @todos). Apagada vira texto padrão, então deixa de casar.
  def marcado_nao_lido?(conversation, user)
    mensagens = mensagens_nao_lidas(conversation, user)
    return false unless mensagens

    padroes = ["%(mention://user/#{user.id}/%"]
    padroes << '%(mention://todos/0/todos)%' if tipo(conversation) == 'grupo'
    mensagens.exists?([(['messages.content LIKE ?'] * padroes.size).join(' OR '), *padroes])
  end

  # Título do push de @ na Equipe; nil (título nativo) fora dela ou sem remetente usuário.
  def titulo_marcacao(notification)
    conversation = notification.primary_actor
    return unless notification.notification_type == 'conversation_mention' && conversation.inbox&.equipe?

    quem = notification.secondary_actor.try(:sender).try(:available_name)
    return unless quem

    chave = tipo(conversation) == '1a1' ? 'equipe_mention_1a1' : 'equipe_mention'
    I18n.t("notifications.notification_title.#{chave}", quem: quem, canal: conversation.contact&.name)
  end

  # nil quando a pessoa não participa.
  def mensagens_nao_lidas(conversation, user)
    participante = user && conversation.conversation_participants.find_by(user_id: user.id)
    return unless participante

    mensagens = conversation.messages.where(sender_type: 'User').where.not(sender_id: user.id)
    participante.last_seen_at ? mensagens.where('messages.created_at > ?', participante.last_seen_at) : mensagens
  end

  # ponytail: 1 contagem por conversa de que participa (dezenas); vira um SQL só se a equipe crescer muito.
  def total_nao_lidas(account, user)
    inbox = caixa(account)
    return 0 unless inbox

    inbox.conversations.where(id: user.conversation_participants.select(:conversation_id)).sum { |c| nao_lidas(c, user) }
  end

  # Quem não participa não grava nem transmite. Só acende os ✓✓ quando havia mensagem de colega por ler: nao_lidas
  # antes de gravar, senão daria sempre zero.
  def marcar_lida(conversation, user)
    participante = conversation.conversation_participants.find_by(user_id: user.id)
    return unless participante

    havia_nova = nao_lidas(conversation, user).positive?
    participante.update!(last_seen_at: Time.current)
    transmitir_leitura(conversation, participante) if havia_nova
  end

  # Participantes + admins, os mesmos que veem a conversa ao vivo (ActionCableListener#user_tokens).
  def transmitir_leitura(conversation, participante)
    pessoas = User.where(id: conversation.conversation_participants.select(:user_id)).pluck(:pubsub_token)
    tokens = (pessoas + conversation.account.administrators.pluck(:pubsub_token)).uniq
    payload = { conversation_id: conversation.display_id, user_id: participante.user_id,
                last_seen_at: participante.last_seen_at.to_i, account_id: conversation.account_id }
    ActionCableBroadcastJob.perform_later(tokens, 'ramon.equipe.lida', payload)
  end

  def participante?(conversation, user)
    user.is_a?(User) && conversation.conversation_participants.exists?(user_id: user.id)
  end

  # Admin de fora só lê. Fora da Equipe nada muda (inclusive AgentBot/usuário nulo).
  def pode_escrever?(conversation, user)
    !conversation.inbox.equipe? || participante?(conversation, user)
  end

  def http_permitido?(conversation, controller_path, action)
    !conversation.inbox.equipe? || HTTP_PERMITIDO.fetch(controller_path, []).include?(action)
  end

  # Caminho que pega conversa por id sem política (ferramenta de IA, fluxo na mão): nunca alcança a Equipe.
  def fora_da_caixa(conversations) = conversations.where.not(inbox_id: Inbox.where(equipe: true).select(:id))

  def contato?(contact) = contact&.additional_attributes.to_h['equipe'].present?

  # Ação em lote (macro, ação em massa) que inclui conversa da Equipe. Os ids são display_id.
  def inclui_conversa?(account, display_ids)
    account.conversations.joins(:inbox).exists?(display_id: display_ids, inboxes: { equipe: true })
  end

  def pode_apagar?(message, user, account_user)
    conversation = message.conversation
    return true unless conversation.inbox.equipe?

    participante?(conversation, user) && (account_user&.administrator? || (message.sender_type == 'User' && message.sender_id == user.id))
  end

  def reacao_valida?(message, emoji)
    EMOJIS_REACAO.include?(emoji) && !message.content_attributes['deleted']
  end

  # Uma reação por pessoa: emoji novo soma, outro troca, o mesmo tira. O nome fica gravado para sobreviver à saída da
  # pessoa. Só muda content_attributes: sem mexer em content nem em last_activity_at, e o message.updated é surdo na Equipe.
  def reagir(message, user, emoji)
    message.with_lock do
      next if message.content_attributes['deleted'] # apagada enquanto esperava a trava

      reacoes = message.content_attributes['ramon_reacoes'].to_a
      repetida = reacoes.any? { |r| r['user_id'] == user.id && r['emoji'] == emoji }
      reacoes = reacoes.reject { |r| r['user_id'] == user.id }
      reacoes += [{ 'user_id' => user.id, 'user_name' => user.available_name, 'emoji' => emoji }] unless repetida
      message.update!(content_attributes: message.content_attributes.merge('ramon_reacoes' => reacoes))
    end
    message
  end

  def tipo(conversation)
    conversation.contact_inbox&.source_id.to_s.start_with?('equipe-1a1-') ? '1a1' : 'grupo'
  end

  def pessoas_1a1(conversation)
    return [] unless tipo(conversation) == '1a1'

    User.where(id: conversation.conversation_participants.select(:user_id)).order(:id).map do |u|
      { id: u.id, name: u.available_name, thumbnail: u.avatar_url }
    end
  end

  # Hub surdo (AsyncDispatcher): o evento é da caixa Equipe?
  def evento?(data)
    return contato?(data[:contact]) if data[:contact].is_a?(Contact)

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
    # Quem entra começa com tudo lido (sem herdar o histórico como não-lido). Dois commits ao mesmo tempo: o outro já criou.
    (user_ids - atuais).each do |user_id|
      conversation.conversation_participants.create!(user_id: user_id, last_seen_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end
end
