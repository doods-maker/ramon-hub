# Prazo de 1ª resposta do lead (SLA da inbox, fallback no env — Ramon::Cadencia).
# Usado pelo SDR ("Responder agora") e pelo gestor ("passaram dos 5 minutos").
# `joins` na conversa/inbox: lead sem conversa (ou conversa apagada) some da lista.
module Ramon::Hoje::Prazo
  module_function

  JANELA = 48.hours

  def sem_resposta(leads)
    leads.funil.joins(conversation: :inbox)
         .where(inboxes: { auto_create_lead: true })
         .where(conversations: { first_reply_created_at: nil, status: Conversation.statuses[:open], created_at: JANELA.ago.. })
         .preload(:thesis, conversation: :inbox)
         .reorder('conversations.created_at')
  end

  def estourados(leads)
    sem_resposta(leads)
      .where("EXTRACT(EPOCH FROM (? - conversations.created_at)) / 60.0 > (#{Ramon::Cadencia.sla_threshold_sql})", Time.current)
  end

  def linha(lead)
    conversa = lead.conversation
    {
      lead_id: lead.id, nome: lead.name, tese: lead.thesis&.name, canal: Ramon::SourceCatalog.labels[lead.channel] || lead.channel,
      conversa_id: conversa.display_id,
      prazo_em: (conversa.created_at + Ramon::Cadencia.sla_minutes(conversa.inbox).minutes).iso8601,
      ultima_mensagem: conversa.messages.incoming.last&.content.to_s.truncate(80)
    }
  end
end
