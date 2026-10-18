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
    agendar_observador(message)
    return unless message.incoming?

    Whatsapp::OneoffCampaignService.opt_out!(message) # "parar"/"sair"... revoga o marketing (LGPD)

    lead = message.account.leads.find_by(conversation_id: message.conversation_id) || lead_da_resposta(message)
    return if lead.blank?

    Ramon::LeadDaConversa.origem(lead, message)
    Ramon::DocMatchJob.perform_later(message.id) if message.attachments.any? { |a| TIPOS_ANEXO.include?(a.file_type) }
    Ramon::CoachObjecaoJob.perform_later(message.id) if message.content.to_s.strip.length >= Ramon::CoachObjecaoService::MIN_CHARS
  end

  # Conversa aberta pelo celular da equipe (Ramon::LeadDaConversa.cabe?) não criou lead; ele nasce na 1ª resposta do cliente.
  # Sem SLA: o eco já conta como 1ª resposta.
  def lead_da_resposta(message)
    conversation = message.conversation
    return unless Ramon::LeadDaConversa.eco?(conversation.messages.first) && conversation.messages.incoming.where.not(id: message.id).none?
    return unless Ramon::LeadDaConversa.cabe?(conversation)

    Ramon::LeadDaConversa.criar_ou_ligar(conversation)
  end

  # Funil automático: incoming ou outgoing público de lead aberto agenda o observador (10 min, debounce no job).
  def agendar_observador(message)
    return if message.private? || !message.message_type.in?(%w[incoming outgoing])
    return unless Ramon::FunilObservadorJob.ativo?(message.account)

    lead = message.account.leads.find_by(conversation_id: message.conversation_id, won_at: nil, lost_at: nil)
    return if lead.blank?

    Ramon::FunilObservadorJob.set(wait: Ramon::FunilObservadorJob::ESPERA).perform_later(message.id)
  end

  # Envio da IA (ou sem autor) que falhou — a Meta recusou na hora ou devolveu "failed" depois — com a conversa ainda com a
  # IA: abre para a equipe pelo caminho da tool de handoff (bot_handoff! avisa a caixa). Senão o lead fica sem resposta.
  def message_updated(event)
    message = event.data[:message]
    return unless event.data[:previous_changes]&.dig('status')&.last == 'failed'

    Whatsapp::OneoffCampaignService.opt_out!(message) # 131050: a pessoa parou de receber marketing na Meta
    return unless message.outgoing? && message.sender_type.in?([nil, 'Captain::Assistant'])

    message.conversation.bot_handoff! if message.conversation.pending?
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
