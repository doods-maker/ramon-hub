# Escrita com aprovacao: propoe gerar contrato + procuracao no ZapSign. O
# documento so nasce quando o humano aplica a sugestao no Cockpit.
class Captain::Tools::PrepararContratoZapsignTool < Captain::Tools::RamonEscritaTool
  description 'Prepara o contrato de honorarios + procuracao do caso no ZapSign. NAO gera o documento: cria uma ' \
              'sugestao que fica pendente para o humano aprovar no Cockpit. Use quando o cliente decidir fechar.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :motivo, type: 'string', desc: 'Por que o contrato deve ser preparado agora', required: false

  def perform(tool_context, lead_id: nil, motivo: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    pronto = lead.custom_attributes&.dig('zapsign', 'sign_url')
    return "O caso #{lead.name} ja tem contrato preparado no ZapSign: #{pronto}" if pronto.present?

    log_tool_usage('preparar_contrato_zapsign', { lead_id: lead.id })
    sugerir(lead, acao: 'zapsign', texto: "Preparar contrato + procuracao no ZapSign para #{lead.name}",
                  justificativa: motivo.presence || 'pedido pelo agente durante o atendimento')
  end
end
