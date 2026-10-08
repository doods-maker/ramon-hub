# frozen_string_literal: true

# Leads e conversas. B5-leads: cada efeito decide UMA vez, por evento, entre o código de sempre e o fluxo migrado
# (Ramon::Fluxos::Migracao.decidir — com reserva: fluxo no comando que não pega o evento devolve aquele evento ao código).
# A ordem é a de sempre (spec: "leads e conversas — código ou fluxo"): o lead nasce ANTES do SLA e dos fluxos comuns de
# Conversa nova; a origem é gravada ANTES dos fluxos comuns de Mensagem recebida — os migrados de criar lead e de origem
# rodam na hora (Disparo::NA_HORA_CHAVES) e o RamonFluxoListener vem depois deste no AsyncDispatcher.
class RamonLeadListener < BaseListener
  TIPOS_ANEXO = %w[image file].freeze # anexo que a IA tenta casar com o checklist

  def conversation_created(event)
    conversation = event.data[:conversation]
    return unless Ramon::LeadDaConversa.cabe?(conversation)

    dados = { 'caixa_id' => conversation.inbox_id }
    decidir('criar_lead', 'conversa_criada', conversation, dados) { Ramon::LeadDaConversa.criar_ou_ligar(conversation) }
    # SLA da 1ª resposta (mapa comercial): o vigia dispara N min depois (SLA da caixa, senão o env) e só apita se a conversa
    # seguir aberta e sem resposta. B4.2: com o fluxo "SLA da 1ª resposta" no comando e vigiando a conversa, o job não é agendado.
    decidir('sla', 'conversa_criada', conversation, dados) do
      Ramon::FirstResponseSlaJob.set(wait: Ramon::Cadencia.sla_minutes(conversation.inbox).minutes).perform_later(conversation.id)
    end
  end

  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    efeitos_da_mensagem(lead, message) if lead
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

  private

  def decidir(grupo, gatilho, alvo, dados, &) = Ramon::Fluxos::Migracao.decidir(grupo, gatilho, alvo, dados, &)

  # Mensagem do cliente numa conversa com lead, na ordem de sempre: origem (na hora) → sugestão de documento (anexo) →
  # coach de objeção (texto com 20+ caracteres). Colheita NÃO é automática (decisão 20/07).
  def efeitos_da_mensagem(lead, message)
    conversa = message.conversation
    dados = dados_da_mensagem(message)
    if Ramon::LeadDaConversa.origem_pendente?(lead, message)
      decidir('origem_lead', 'mensagem_recebida', conversa, dados) { Ramon::LeadDaConversa.origem(lead, message) }
    end
    if message.attachments.any? { |a| TIPOS_ANEXO.include?(a.file_type) }
      decidir('sugestao_doc', 'mensagem_recebida', conversa, dados) { Ramon::DocMatchJob.perform_later(message.id) }
    end
    return if message.content.to_s.strip.length < Ramon::CoachObjecaoService::MIN_CHARS

    decidir('coach', 'mensagem_recebida', conversa, dados) { Ramon::CoachObjecaoJob.perform_later(message.id) }
  end

  def dados_da_mensagem(message)
    { 'caixa_id' => message.conversation.inbox_id, 'mensagem_id' => message.id, 'texto' => message.content.to_s.truncate(500) }
  end
end
