# Sino + push da IA para a equipe (roteiro da tese, limites dos modos "sozinha até…", dados do contrato): ao
# closer/SDR do lead e, sem eles ou quando pedido (roteiro sem saída, spec §5), também aos administradores da conta.
module Ramon::AvisoDaIa
  RASCUNHO_TRAVA = 10.minutes

  module_function

  def avisar(lead, label, titulo, corpo, admins: false)
    ids = [lead.closer_id || lead.sdr_id].compact
    ids |= Ramon::Papeis.gestor_ids(lead.account) if admins || ids.empty?
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: ids,
                                       meta: { 'label' => label.truncate(200) }).perform
    Ramon::NtfyPushJob.perform_later(lead.id, title: titulo, body: corpo.to_s.truncate(200))
  end

  # Resposta da IA que virou RASCUNHO no atendimento (ResponseBuilderJob): a nota privada não notifica e a conversa
  # pending fica fora do SLA — sem isto o lead fica sem resposta e ninguém sabe. 1 aviso por conversa a cada 10 min.
  def rascunho(lead)
    chave = "RAMON::IA_RASCUNHO::#{lead&.conversation_id}"
    return unless lead&.conversation_id && Redis::Alfred.set(chave, 1, nx: true, ex: RASCUNHO_TRAVA.to_i)

    avisar(lead, "IA deixou um rascunho para #{lead.name} - revise e envie", "IA: rascunho para #{lead.name}",
           'Revise o rascunho na conversa e envie')
  end
end
