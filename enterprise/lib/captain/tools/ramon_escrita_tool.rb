# Base das tools de ESCRITA do agente.
#
# Regra do estatuto virando arquitetura (spec da area de IA, secao 6): nenhuma
# tool de escrita executa direto. Toda tool daqui apenas cria uma sugestao
# PENDENTE — o humano revisa no Cockpit e clica em aplicar; so entao a acao
# acontece de verdade (CopilotSuggestion#apply!).
class Captain::Tools::RamonEscritaTool < Captain::Tools::RamonBaseTool
  private

  # Idempotencia: sugestao pendente igual (mesmo caso, mesma acao) nao vira duas.
  def sugerir(lead, acao:, texto:, **extras)
    pendente = pendente_para(lead, acao)
    return "Ja existe uma sugestao pendente para isso no caso #{lead.name} — o humano ainda nao aplicou." if pendente

    lead.account.copilot_suggestions.create!(
      lead: lead, kind: 'acao', status: 'pending', run_at: Time.current,
      payload: { 'acao' => acao, 'texto' => texto, 'lead_name' => lead.name,
                 'stage_name' => lead.lead_stage&.name }.merge(extras.stringify_keys)
    )
    "Preparei a sugestao e ela esta pendente de aprovacao no Cockpit: #{texto}. Nada foi executado ainda."
  end

  def pendente_para(lead, acao)
    lead.account.copilot_suggestions.pending
        .where(lead_id: lead.id, kind: 'acao')
        .find { |s| s.payload['acao'] == acao }
  end
end
