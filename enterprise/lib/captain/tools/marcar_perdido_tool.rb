# Escrita com aprovacao: propoe marcar o caso como perdido. Perdido tira o caso
# do funil ativo — so o humano aplica, no Cockpit (CopilotSuggestion 'perdido').
class Captain::Tools::MarcarPerdidoTool < Captain::Tools::RamonEscritaTool
  description 'Propoe marcar o caso como perdido com um motivo do catalogo. NAO marca: cria uma sugestao pendente ' \
              'que o humano aprova no Cockpit.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :motivo, type: 'string', desc: 'Motivo da perda (nome do catalogo do funil, ou parte dele)', required: true

  def perform(tool_context, motivo: nil, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?
    return "O caso #{lead.name} ja esta ganho — nao da para marcar perdido." if lead.won_at.present?
    return "O caso #{lead.name} ja esta marcado como perdido." if lead.lost_at.present?

    motivos = lead.account.lost_reasons.map(&:name)
    escolhido = casar(motivos, motivo)
    return "Motivo nao encontrado. Os motivos do funil sao: #{motivos.join(', ')}." if escolhido.blank?

    log_tool_usage('marcar_perdido', { lead_id: lead.id, motivo: escolhido })
    sugerir(lead, acao: 'perdido', texto: "Marcar #{lead.name} como perdido — motivo: #{escolhido}", lost_reason: escolhido)
  end

  private

  def casar(motivos, texto)
    alvo = I18n.transliterate(texto.to_s).downcase.strip
    return nil if alvo.blank?

    motivos.find { |m| I18n.transliterate(m).downcase == alvo } ||
      motivos.find { |m| I18n.transliterate(m).downcase.include?(alvo) }
  end
end
