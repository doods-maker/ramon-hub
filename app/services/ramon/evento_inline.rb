# Evento de automação visível na conversa (Onda B): activity message com
# content_attributes['ramon_event'] que o front renderiza como bolha própria
# ("o hub trabalhando à vista"). Activity nunca é entregue ao contato
# (action_cable_listener descarta activity do token do contato) — interno
# por construção.
module Ramon::EventoInline
  module_function

  # extra: só valores JSON-nativos e chaves string (Sidekiq strict_args).
  def registrar(conversation, texto, tipo:, extra: {})
    return if conversation.blank?

    Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: texto,
      content_attributes: { 'ramon_event' => tipo }.merge(extra)
    )
  end
end
