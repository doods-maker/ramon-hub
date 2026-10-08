# Automações em fluxo: traduz eventos do hub em gatilhos de fluxo (spec §4.1).
# `performed_by` = execução de fluxo que causou o evento (cadeia/profundidade).
class RamonFluxoListener < BaseListener
  def conversation_created(event) = disparar('conversa_criada', event.data[:conversation], event)

  def conversation_resolved(event) = disparar('conversa_resolvida', event.data[:conversation], event)

  def conversation_opened(event) = disparar('conversa_reaberta', event.data[:conversation], event)

  # A atribuição automática emite um 2º evento sem :changed_attributes (duplicata do do modelo) — ignorar.
  def assignee_changed(event)
    return unless event.data.key?(:changed_attributes)

    disparar('conversa_atribuida', event.data[:conversation], event)
  end

  # Mensagem do cliente → mensagem_recebida; nota privada de alguém da equipe (B5-leads) → nota_escrita. Notas escritas
  # pelos fluxos não têm autor (Passos::Conversa#escrever) e não disparam nada. mensagem_id: as rotinas prontas leem a mensagem.
  def message_created(event)
    message = event.data[:message]
    dados = { 'texto' => message.content.to_s.truncate(500), 'mensagem_id' => message.id }
    if message.incoming? && !message.private?
      disparar('mensagem_recebida', message.conversation, event, dados)
    elsif message.private? && message.sender.is_a?(User)
      disparar('nota_escrita', message.conversation, event, dados)
    end
  end

  def lead_created(event) = disparar('lead_criado', event.data[:lead], event)

  def lead_updated(event)
    de, para = (event.data[:changed_attributes] || {})['lead_stage_id']
    return if para.nil?

    lead = event.data[:lead]
    etapa = LeadStage.find_by(id: para) # a etapa do evento, não a de agora (o lead pode ter andado de novo)
    dados = { 'de_etapa_id' => de, 'para_etapa_id' => para }
    disparar('lead_mudou_etapa', lead, event, dados)
    disparar('lead_ganho', lead, event, dados) if etapa&.is_won
    disparar('lead_perdido', lead, event, dados) if etapa&.is_lost
  end

  private

  def disparar(tipo, alvo, event, dados = {})
    return if alvo.nil?

    base = alvo.is_a?(Conversation) ? { 'caixa_id' => alvo.inbox_id } : {}
    autor = event.data[:performed_by]
    Ramon::Fluxos::Disparo.call(tipo, alvo, base.merge(dados), origem: autor.is_a?(FluxoExecucao) ? autor : nil)
  end
end
