# Freio do atendimento da IA, na entrada de cada turno do Captain::Conversation::ResponseBuilderJob (antes do LLM).
# Freou → a conversa vai para a fila humana (bot_handoff!) e o turno sai sem resposta.
# - Atribuída a uma pessoa: um humano assumiu (atribuir não muda o status, a conversa seguia pending). A atribuição
#   automática ao SDR do lead (LeadComercial#assign_conversation_to_sdr) não conta: toda conversa de lead nasce com ela
#   e a IA atende na frente do SDR. Resposta humana já abre a conversa sozinha (Message#human_response?).
module Ramon::IaFreio
  module_function

  # @return [Boolean] true = freou (o job para aqui)
  def entregar!(conversa, lead)
    motivo = motivo(conversa, lead)
    return false unless motivo

    Rails.logger.info("[Ramon::IaFreio] conversa #{conversa.id}: #{motivo} - vai para a fila humana")
    conversa.bot_handoff!
    true
  end

  def motivo(conversa, lead)
    'atribuida' if conversa.assignee_id.present? && conversa.assignee_id != lead&.sdr_id
  end
end
