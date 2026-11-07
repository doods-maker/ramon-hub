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
    ligar_cobranca(lead)
    registrar(lead, 'Entrou em Documentos: a conversa voltou para o assistente da etapa')
  end

  # Relógio da cobrança (Ramon::Documentos::CobrancaJob) do zero a cada entrada: a abertura sai na próxima rodada. Sem IA, não
  # liga (quem conduz é a pessoa avisada). update_columns: sem os callbacks de cadência (lição do B4.3).
  def ligar_cobranca(lead)
    relogio = { Ramon::Documentos::Relogio::CHAVE => { 'entrou_em' => Time.current.iso8601 } }
    lead.with_lock { lead.update_columns(custom_attributes: lead.custom_attributes.merge(relogio)) } # rubocop:disable Rails/SkipsModelValidations
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
