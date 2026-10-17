# Gatilho do funil -> aviso de conversão à Meta (um por lead e evento). Só leads de anúncio (ctwa_clid) e com a chave ligada.
class Ramon::MetaConversoes
  LABEL_EVENTO = { 'fase-qualificacao' => 'LeadSubmitted', 'fase-reuniao-agendada' => 'QualifiedLead',
                   'fase-reuniao-realizada' => 'InitiateCheckout' }.freeze

  def self.ligado? = ENV.fetch('RAMON_META_CAPI', 'off') == 'on'

  # Devolve o último MetaEvento criado (ou nil).
  def self.registrar(lead)
    return unless ligado? && lead.custom_attributes.to_h.dig('meta_referral', 'ctwa_clid').present?

    eventos_de(lead).filter_map { |evento| criar(lead, evento) }.last
  rescue StandardError => e
    # O aviso nunca pode derrubar o update! do lead.
    ChatwootExceptionTracker.new(e, account: lead.account).capture_exception
    Rails.logger.error("Ramon::MetaConversoes #{e.class} lead_id=#{lead.id}")
    nil
  end

  def self.eventos_de(lead)
    compra = ('Purchase' if lead.saved_change_to_won_at? && lead.won_at.present?)
    etapa = (LABEL_EVENTO[lead.lead_stage&.label] if lead.saved_change_to_lead_stage_id?)
    [compra, etapa].compact
  end

  def self.criar(lead, evento)
    registro = MetaEvento.create!(account_id: lead.account_id, lead_id: lead.id, evento: evento,
                                  event_id: "lead-#{lead.id}-#{evento}", ocorrido_em: Time.current)
    enfileirar(registro)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.enfileirar(registro)
    Ramon::MetaConversaoJob.perform_later(registro.id)
    registro
  rescue StandardError
    registro.update(status: 'erro', erro: 'fila_indisponivel') # não deixa pendente órfão
    registro
  end
end
