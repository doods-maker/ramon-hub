# Sino + push da IA para a equipe (roteiro da tese, limites dos modos "sozinha até…", dados do contrato): ao
# closer/SDR do lead e, sem eles ou quando pedido (roteiro sem saída, spec §5), também aos administradores da conta.
module Ramon::AvisoDaIa
  module_function

  def avisar(lead, label, titulo, corpo, admins: false)
    ids = [lead.closer_id || lead.sdr_id].compact
    ids |= Ramon::Papeis.gestor_ids(lead.account) if admins || ids.empty?
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: ids,
                                       meta: { 'label' => label.truncate(200) }).perform
    Ramon::NtfyPushJob.perform_later(lead.id, title: titulo, body: corpo.to_s.truncate(200))
  end
end
