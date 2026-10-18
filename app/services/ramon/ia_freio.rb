# Freio do atendimento da IA, na entrada de cada turno do Captain::Conversation::ResponseBuilderJob (antes do LLM).
# Freou → a conversa vai para a fila humana (bot_handoff!) e o turno sai sem resposta.
# - Atribuída a uma pessoa: um humano assumiu (atribuir não muda o status, a conversa seguia pending). A atribuição
#   automática ao SDR do lead (LeadComercial#assign_conversation_to_sdr) não conta: toda conversa de lead nasce com ela
#   e a IA atende na frente do SDR. Resposta humana já abre a conversa sozinha (Message#human_response?).
# - Gasto do dia no teto da conta (Ramon::IaGastoAlerta): até aqui o teto só parava FAQ, memória e caderno.
# - Respostas demais na última hora (auto-resposta de outra empresa = pingue-pongue o dia todo); rascunho conta: é LLM pago.
module Ramon::IaFreio
  # ponytail: teto fixo de 15 respostas da IA por conversa por hora; vira configuração da conta se precisar ajustar.
  RESPOSTAS_POR_HORA = 15

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
    return 'atribuida' if conversa.assignee_id.present? && conversa.assignee_id != lead&.sdr_id
    return 'teto_de_gasto' if Ramon::IaGastoAlerta.passou_do_teto?(conversa.account)

    'respostas_por_hora' if respostas_na_ultima_hora(conversa) > RESPOSTAS_POR_HORA
  end

  def respostas_na_ultima_hora(conversa)
    conversa.messages.outgoing.where(sender_type: 'Captain::Assistant', created_at: 1.hour.ago..).count
  end
end
