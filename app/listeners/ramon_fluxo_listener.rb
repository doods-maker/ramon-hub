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

  def message_created(event)
    message = event.data[:message]
    return unless message.incoming? && !message.private?

    disparar('mensagem_recebida', message.conversation, event, 'texto' => message.content.to_s.truncate(500))
  end

  def lead_created(event) = disparar('lead_criado', event.data[:lead], event)

  def lead_updated(event)
    de, para = (event.data[:changed_attributes] || {})['lead_stage_id']
    return if para.nil?

    lead = event.data[:lead]
    dados = { 'de_etapa_id' => de, 'para_etapa_id' => para }
    disparar('lead_mudou_etapa', lead, event, dados)
    disparar('lead_ganho', lead, event, dados) if lead.lead_stage&.is_won
    disparar('lead_perdido', lead, event, dados) if lead.lead_stage&.is_lost
  end

  private

  def disparar(tipo, alvo, event, dados = {})
    return if alvo.nil?

    base = alvo.is_a?(Conversation) ? { 'caixa_id' => alvo.inbox_id } : {}
    autor = event.data[:performed_by]
    Ramon::Fluxos::Disparo.call(tipo, alvo, base.merge(dados), origem: autor.is_a?(FluxoExecucao) ? autor : nil)
  end
end
