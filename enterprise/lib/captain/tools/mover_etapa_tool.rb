# Escrita com aprovacao: propoe mover o caso de etapa no funil. Reusa o tipo
# move_stage que o copiloto noturno ja usa — o Cockpit ja sabe desenhar e
# aplicar, cartao a cartao (nunca em massa).
#
# Guardrail: so etapa aberta entra na lista. Ganho e perdido ficam de fora,
# porque ganho dispara a abertura do caso no AdvBox de verdade (PR #96).
class Captain::Tools::MoverEtapaTool < Captain::Tools::RamonEscritaTool
  description 'Propoe mover o caso para outra etapa do funil. NAO move: cria uma sugestao pendente que o humano ' \
              'aprova no Cockpit. Nao serve para marcar ganho nem perdido.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :etapa, type: 'string', desc: 'Nome exato da etapa de destino', required: true
  param :motivo, type: 'string', desc: 'Por que o caso deve mudar de etapa', required: false

  def perform(tool_context, etapa: nil, lead_id: nil, motivo: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    destino = etapas_abertas(lead).find { |stage| stage.name.casecmp?(etapa.to_s.strip) }
    return "Etapa nao encontrada. As etapas disponiveis sao: #{etapas_abertas(lead).map(&:name).join(', ')}." if destino.blank?
    return "O caso #{lead.name} ja esta na etapa #{destino.name}." if destino.id == lead.lead_stage_id

    log_tool_usage('mover_etapa', { lead_id: lead.id, etapa: destino.name })
    criar_sugestao(lead, destino, motivo)
  end

  private

  def etapas_abertas(lead)
    lead.account.lead_stages.where(is_won: false, is_lost: false).order(:position)
  end

  def criar_sugestao(lead, destino, motivo)
    pendente = lead.account.copilot_suggestions.pending.exists?(lead_id: lead.id, kind: 'move_stage')
    return "Ja existe uma sugestao de mudanca de etapa pendente no caso #{lead.name}." if pendente

    lead.account.copilot_suggestions.create!(
      lead: lead, kind: 'move_stage', status: 'pending', run_at: Time.current,
      payload: { 'etapa_sugerida' => destino.name, 'lead_name' => lead.name,
                 'stage_name' => lead.lead_stage&.name,
                 'justificativa' => motivo.presence || 'pedido pelo agente durante o atendimento' }
    )
    "Sugeri mover #{lead.name} para #{destino.name}. Fica pendente ate o humano aprovar no Cockpit."
  end
end
