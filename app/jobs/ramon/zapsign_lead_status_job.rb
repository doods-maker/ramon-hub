# Contrato do lead (cartão ZapSign do painel): confere no ZapSign o status real
# do doc (o payload do webhook não é a verdade) e grava o selo assinado/recusado
# em custom_attributes['zapsign'] + histórico + sino. NUNCA marca o lead como
# ganho: ganho dispara AdvBox/Drive/NPS e continua sendo decisão do closer.
class Ramon::ZapsignLeadStatusJob < ApplicationJob
  queue_as :low
  retry_on Ramon::ZapsignClient::UnavailableError, wait: :polynomially_longer, attempts: 5

  # status do ZapSign => [kind da atividade, chave da data, rótulo do sino, gatilho de fluxo]
  STATUS = {
    'signed' => %w[zapsign_signed assinado_em assinado contrato_assinado],
    'refused' => %w[zapsign_refused recusado_em recusado contrato_recusado]
  }.freeze

  def perform(lead_id, doc_token)
    return unless atual?(Lead.find_by(id: lead_id), doc_token)

    doc = Ramon::ZapsignClient.doc(doc_token)
    kind, chave, rotulo, gatilho = STATUS[doc['status'].to_s]
    # reload depois do HTTP: o "Gerar de novo" pode ter trocado o doc no meio
    lead = Lead.find_by(id: lead_id)
    return if kind.nil? || !atual?(lead, doc_token)

    zapsign = lead.custom_attributes['zapsign'].merge('status' => doc['status'], chave => data_do_evento(doc))
    lead.update!(custom_attributes: lead.custom_attributes.merge('zapsign' => zapsign))
    lead.lead_activities.create!(account: lead.account, kind: kind, to_value: zapsign['template_name'])
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_contract_status', meta: { 'label' => rotulo }).perform
    Ramon::Fluxos::Disparo.externo(gatilho, lead)
  end

  private

  # Só o doc vigente do lead e só a 1ª mudança: doc trocado ("Gerar de novo"),
  # cancelado por nós ou já assinado/recusado não gera selo nem sino de novo.
  def atual?(lead, doc_token)
    zapsign = lead&.custom_attributes&.dig('zapsign') || {}
    zapsign['doc_token'] == doc_token && zapsign['status'].blank?
  end

  def data_do_evento(doc)
    Array(doc['signers']).filter_map { |s| s['signed_at'] }.max || Time.zone.now.iso8601
  end
end
