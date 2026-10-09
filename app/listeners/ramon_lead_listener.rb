# frozen_string_literal: true

# Leads e conversas (regra fixa, decisão do Eduardo 08/10): criar lead, origem, sugestão de documento e coach rodam aqui,
# no código, sempre. Só o SLA da 1ª resposta decide entre o código e o fluxo "SLA da 1ª resposta" (Migracao.decidir, com
# reserva). A ordem é a de sempre: o lead nasce ANTES do SLA e dos fluxos comuns de Conversa nova; a origem é gravada
# ANTES dos fluxos comuns de Mensagem recebida (o RamonFluxoListener vem depois deste no AsyncDispatcher).
class RamonLeadListener < BaseListener
  TIPOS_ANEXO = %w[image file].freeze # anexo que a IA tenta casar com o checklist

  def conversation_created(event)
    conversation = event.data[:conversation]
    return unless Ramon::LeadDaConversa.cabe?(conversation)

    Ramon::LeadDaConversa.criar_ou_ligar(conversation)
    # SLA da 1ª resposta (mapa comercial): o vigia dispara N min depois (SLA da caixa, senão o env) e só apita se a conversa
    # seguir aberta e sem resposta. B4.2: com o fluxo "SLA da 1ª resposta" no comando e vigiando a conversa, o job não é agendado.
    Ramon::Fluxos::Migracao.decidir('sla', 'conversa_criada', conversation, 'caixa_id' => conversation.inbox_id) do
      Ramon::FirstResponseSlaJob.set(wait: Ramon::Cadencia.sla_minutes(conversation.inbox).minutes).perform_later(conversation.id)
    end
  end

  # Mensagem do cliente numa conversa com lead: origem → sugestão de documento (anexo) → coach de objeção (texto com 20+
  # caracteres). Colheita NÃO é automática (decisão 20/07).
  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    return if lead.blank?

    Ramon::LeadDaConversa.origem(lead, message)
    Ramon::DocMatchJob.perform_later(message.id) if message.attachments.any? { |a| TIPOS_ANEXO.include?(a.file_type) }
    Ramon::CoachObjecaoJob.perform_later(message.id) if message.content.to_s.strip.length >= Ramon::CoachObjecaoService::MIN_CHARS
  end

  def lead_created(event)
    Ramon::StageLabelSync.apply_to_conversation(event.data[:lead])
    Ramon::TeseLabelSync.apply_to_conversation(event.data[:lead])
  end

  def lead_updated(event)
    Ramon::StageLabelSync.apply_to_conversation(event.data[:lead])
    Ramon::TeseLabelSync.apply_to_conversation(event.data[:lead])
  end

  def conversation_updated(event)
    conversation = event.data[:conversation]
    changes = event.data[:changed_attributes]
    return if changes.blank?

    label_change = changes['label_list'] || changes[:label_list]
    return if label_change.blank?

    old_labels, new_labels = label_change
    added = Array(new_labels) - Array(old_labels)
    Ramon::StageLabelSync.apply_to_lead(conversation, added)
  end
end
