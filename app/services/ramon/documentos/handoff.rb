# A IA passou a conversa para uma pessoa (qualquer bot_handoff!: tool de handoff, gatilho, freio, cota, envio que falhou)
# com o lead na etapa Documentos (spec Etapa Documentos §6; só com a chave ligada, via Ramon::EtapaDeGanho.conduzida?):
# a conversa vai para quem conduz (Ramon::Documentos::Responsavel), com nota privada do motivo e do que falta, e aviso no
# sino + push (só a tese: o ntfy é público). Ninguém online (ou ninguém no lead): os admins também são avisados.
# Fora de Documentos, o handoff segue o de sempre. Devolver = "Devolver à IA".
module Ramon::Documentos::Handoff
  # A tool de handoff grava o motivo numa nota privada com esta marca em content_attributes, logo antes do bot_handoff!.
  MARCA = 'ramon_handoff'.freeze
  # A nota da tool deste handoff: depois da última mensagem do cliente (uma query, subconsulta). Conversa sem mensagem do
  # cliente (a cobrança de Documentos passa por silêncio): qualquer nota marcada vale.
  DEPOIS_DO_CLIENTE = 'messages.created_at > COALESCE((SELECT MAX(m.created_at) FROM messages m WHERE m.conversation_id = ' \
                      "messages.conversation_id AND m.message_type = 0), '-infinity')".freeze

  module_function

  def call(conversa)
    lead = conversa.account.leads.find_by(conversation_id: conversa.id)
    return unless lead && Ramon::EtapaDeGanho.conduzida?(lead.lead_stage)

    responsavel = Ramon::Documentos::Responsavel.de(lead)
    conversa.update!(assignee: responsavel) if responsavel
    Messages::MessageBuilder.new(nil, conversa, { content: nota(conversa, lead, responsavel), private: true }).perform
    Ramon::AvisoDaIa.avisar(lead, "IA passou #{lead.name} (Documentos) para a equipe: veja a nota na conversa",
                            "Documentos: IA passou para a equipe (#{Ramon::NtfyPushJob.rotulo(lead)})", 'Veja a nota na conversa',
                            user_ids: [responsavel&.id].compact,
                            admins: !(responsavel && Ramon::Documentos::Responsavel.online?(lead.account, responsavel)))
  end

  def nota(conversa, lead, responsavel)
    falta = lead.docs_pendentes.pluck(:title)
    [
      "IA passou a conversa (etapa Documentos) para #{responsavel&.name || 'a equipe'}.",
      "Motivo: #{motivo(conversa) || 'passagem automática (sem motivo da IA: freio, cota ou falha de envio).'}",
      "Falta: #{falta.presence&.join(', ') || 'nada no checklist'}."
    ].join("\n")
  end

  def motivo(conversa)
    # content_attributes é store com coder JSON numa coluna json: string JSON, desembrulhada com #>> '{}'
    conversa.messages.where(private: true).where("(content_attributes #>> '{}')::jsonb ->> '#{MARCA}' = 'true'").where(DEPOIS_DO_CLIENTE)
            .order(:created_at).last&.content.presence
  end
end
