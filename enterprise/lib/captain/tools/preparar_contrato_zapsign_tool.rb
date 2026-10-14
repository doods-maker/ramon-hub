# Escrita com aprovacao: propoe gerar contrato + procuracao no ZapSign. O documento so nasce quando o humano aplica a
# sugestao no Cockpit — exceto no modo "sozinha ate o contrato", em que Ramon::ContratoAutomatico gera na hora.
class Captain::Tools::PrepararContratoZapsignTool < Captain::Tools::RamonEscritaTool
  description 'Prepara o contrato de honorarios + procuracao do caso no ZapSign. No modo "sozinha ate o contrato", com ' \
              'o cadastro completo, gera na hora e devolve o link de assinatura para voce enviar ao lead. Nos outros ' \
              'casos cria uma sugestao pendente para o humano aprovar no Cockpit. Use quando o cliente decidir fechar.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :motivo, type: 'string', desc: 'Por que o contrato deve ser preparado agora', required: false

  def perform(tool_context, lead_id: nil, motivo: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    pronto = lead.custom_attributes&.dig('zapsign', 'sign_url')
    return "O caso #{lead.name} ja tem contrato preparado no ZapSign: #{pronto}" if pronto.present?

    log_tool_usage('preparar_contrato_zapsign', { lead_id: lead.id })
    na_hora = ::Ramon::ContratoAutomatico.preparar(lead)
    return "Contrato gerado. Envie este link ao lead para assinar pelo celular: #{na_hora[:link]}" if na_hora&.key?(:link)

    com_falta(sugerir(lead, acao: 'zapsign', texto: "Preparar contrato + procuracao no ZapSign para #{lead.name}",
                            justificativa: motivo.presence || 'pedido pelo agente durante o atendimento'), na_hora)
  end

  private

  def com_falta(sugestao, na_hora)
    return sugestao unless na_hora

    "#{sugestao} Nao deu para gerar na hora (falta: #{na_hora[:falta].join(', ')}): diga que a equipe envia o contrato e passe para humano."
  end
end
