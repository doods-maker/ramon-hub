# Leitura pura: o relogio da prescricao quinquenal do caso (Art. 103, par.
# unico, da Lei 8.213/91), calculado pelo mesmo metodo do Radar de Prescricao.
class Captain::Tools::ChecarPrescricaoTool < Captain::Tools::RamonBaseTool
  description 'Checa a prescricao quinquenal do caso (Art. 103, paragrafo unico, da Lei 8.213/91): quantos meses ' \
              'se passaram desde a DCB, quantas parcelas ja prescreveram, quanto isso vale e quantos meses faltam ' \
              'para o corte dos 5 anos.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    info = lead.prescription
    return "O caso #{lead.name} nao tem DCB registrada — sem DCB nao da para contar a prescricao." if info.blank?

    log_tool_usage('checar_prescricao', { lead_id: lead.id })
    resumo(lead, info).to_json
  end

  private

  def resumo(lead, info)
    {
      lead_id: lead.id,
      nome: lead.name,
      dcb_em: lead.dcb_em,
      meses_desde_dcb: info[:months_since_dcb],
      parcelas_prescritas: info[:lost_installments],
      valor_ja_prescrito: info[:lost_value]&.to_f,
      meses_ate_o_corte: [::Lead::PRESCRIPTION_WINDOW_MONTHS - info[:months_since_dcb], 0].max,
      mensalidade_estimada: lead.benefit_monthly_value&.to_f
    }
  end
end
