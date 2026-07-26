# Escrita com aprovacao: propoe abrir cliente + caso + tarefa no AdvBox. A
# chamada ao AdvBox so acontece quando o humano aplica a sugestao no Cockpit.
#
# Guardrail herdado do PR #96: a IA nunca marca o caso como ganho. Se o caso
# ainda nao foi fechado, esta tool recusa em vez de sugerir.
class Captain::Tools::PrepararCasoAdvboxTool < Captain::Tools::RamonEscritaTool
  description 'Prepara a abertura do caso no AdvBox (cliente + processo + primeira tarefa). NAO escreve no AdvBox: ' \
              'cria uma sugestao pendente para o humano aprovar. So funciona em caso ja marcado como ganho.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false

  SEM_GANHO = 'O caso ainda nao esta marcado como ganho. O AdvBox so recebe caso fechado, e quem fecha e o humano.'.freeze

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?
    return SEM_GANHO if lead.won_at.blank?

    sincronizado = lead.custom_attributes&.dig('advbox', 'sincronizado_em')
    return "O caso #{lead.name} ja foi sincronizado com o AdvBox em #{sincronizado}." if sincronizado.present?

    log_tool_usage('preparar_caso_advbox', { lead_id: lead.id })
    sugerir(lead, acao: 'advbox', texto: "Abrir cliente, caso e primeira tarefa no AdvBox para #{lead.name}")
  end
end
