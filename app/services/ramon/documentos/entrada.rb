# Lead entrou na etapa Documentos (spec Etapa Documentos §2; chamado pelo RamonLeadListener, só com a chave ligada).
# Conversa numa caixa com IA: volta para a IA — pendente (o assistente só responde conversa pendente) e sem Pausa; não
# manda mensagem (a abertura é do PR 5). Sem conversa, ou caixa sem IA: nada de IA; avisa quem conduz os documentos
# (o SDR do lead; sem ele, o closer; sem nenhum, os administradores). Push só com a tese (Ramon::NtfyPushJob.rotulo).
module Ramon::Documentos::Entrada
  module_function

  def call(lead)
    conversa = lead.conversation
    return avisar(lead, conversa ? 'numa caixa sem IA' : 'sem WhatsApp') unless conversa && Captain::AssistenteDaConversa.para(conversa)

    conversa.update!(status: :pending, custom_attributes: Ramon::PerfilIa.com_pausa(conversa.custom_attributes || {}, nil))
    Ramon::Documentos::Cobranca.ligar(lead) # relógio do zero: a abertura sai na próxima rodada. Sem IA, não liga.
    registrar(lead, 'Entrou em Documentos: a conversa voltou para o assistente da etapa')
  end

  def avisar(lead, motivo)
    texto = "Lead em Documentos #{motivo} — conduzir os documentos"
    ids = [lead.sdr_id || lead.closer_id].compact.presence || Ramon::Papeis.gestor_ids(lead.account)
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: ids, meta: { 'label' => texto }).perform
    Ramon::NtfyPushJob.perform_later(lead.id, title: "Documentos: #{Ramon::NtfyPushJob.rotulo(lead)}", body: texto)
    registrar(lead, "Entrou em Documentos #{motivo}: equipe avisada para conduzir os documentos")
  end

  def registrar(lead, texto) = lead.lead_activities.create!(account: lead.account, kind: 'documentos', to_value: texto)
end
