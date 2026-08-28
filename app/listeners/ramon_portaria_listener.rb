# frozen_string_literal: true

# Portaria: menu de Setores na 1ª mensagem de toda conversa nova da caixa do
# escritório (inbox.portaria_enabled). O cliente toca num botão e a conversa
# vai pro Team (Setor) escolhido; texto que não casa reapresenta o menu 1x e
# depois cai na Recepção. Sem estado próprio: tudo é derivado do banco
# (team_id + contagem de menus já enviados), o que torna o retry do Sidekiq
# idempotente.
class RamonPortariaListener < BaseListener
  SETORES = %w[recepção controladoria advogados].freeze
  FALLBACK = 'recepção'
  MAX_MENUS = 2

  def message_created(event)
    message = event.data[:message]
    return unless message.incoming? && message.inbox.portaria_enabled?

    conversation = message.conversation
    return if conversation.team_id.present?

    teams = conversation.account.teams.where(name: SETORES).index_by(&:name)
    return if teams.size < SETORES.size # ponytail: sem os 3 times a Portaria fica dormente

    enviados = conversation.messages.outgoing.where(content_type: 'input_select').count
    if (team = teams[opcao(message)])
      atribuir(conversation, team)
    elsif enviados < MAX_MENUS
      enviar_menu(conversation, enviados.zero? ? 'menu' : 'menu_retry')
    else
      atribuir(conversation, teams[FALLBACK])
    end
  end

  private

  def opcao(message)
    (message.content_attributes['interactive_reply_id'].presence || message.content.to_s).strip.downcase
  end

  def atribuir(conversation, team)
    conversation.update!(team: team)
    return unless team.allow_auto_assign

    # o AutoAssignmentHandler nativo só roda em mudança de status, não de time
    AutoAssignment::AgentAssignmentService.new(conversation: conversation, allowed_agent_ids: team.members.ids).perform
  end

  def enviar_menu(conversation, key)
    # ponytail: 2 mensagens do cliente em <1s podem gerar 2 menus; se acontecer, setnx por conversa (cf. Whatsapp::MessageDedupLock)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: 'input_select',
      content: I18n.t("conversations.messages.portaria.#{key}"),
      content_attributes: { items: SETORES.map { |s| { title: I18n.t("conversations.messages.portaria.setores.#{s}"), value: s } } }
    )
  end
end
