# Leitura pura: aplica a formula de honorario da tese do caso (Ramon::Honorario)
# aos valores que o agente ja tem em maos. Nao chama o motor — e so a conta.
class Captain::Tools::SimularHonorarioTool < Captain::Tools::RamonBaseTool
  description 'Estima o honorario da banca para o caso: aplica a formula da tese do lead ' \
              '(percentual dos atrasados + N mensalidades) aos valores informados. E estimativa, nao proposta.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false
  param :mensal, type: 'number', desc: 'Valor mensal estimado do beneficio (R$)', required: true
  param :atrasados, type: 'number', desc: 'Valor estimado dos atrasados (R$)', required: true

  SEM_TESE = 'O caso ainda nao tem tese definida — defina a tese do lead antes de simular o honorario.'.freeze

  def perform(tool_context, mensal:, atrasados:, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?
    return SEM_TESE if lead.thesis.blank?

    log_tool_usage('simular_honorario', { lead_id: lead.id })
    atrasados_dec = numero(atrasados)
    mensal_dec = numero(mensal)
    resultado = ::Ramon::Honorario.calcular(lead.thesis, atrasados: atrasados_dec, mensal: mensal_dec)
    return "Nao da para simular: #{resultado[:motivo]}." if resultado[:valor].nil?

    texto(resultado, atrasados_dec, mensal_dec)
  rescue StandardError => e
    Rails.logger.error("SimularHonorarioTool: #{e.class}: #{e.message}")
    'Nao consegui simular o honorario agora. Siga sem ele.'
  end

  private

  # O LLM manda numero como string, as vezes com virgula.
  def numero(valor)
    BigDecimal(valor.to_s.tr(',', '.'))
  rescue ArgumentError, TypeError
    BigDecimal(0)
  end

  def texto(res, atrasados, mensal)
    "Honorario estimado (tese #{res[:tese]}): R$ #{res[:valor]}. " \
      "Formula: #{res[:percentual]}% de R$ #{format('%.2f', atrasados)} (atrasados) + " \
      "#{res[:n_mensalidades]} x R$ #{format('%.2f', mensal)} (mensalidades). " \
      'Aviso: estimativa a partir dos valores informados — o valor final depende do calculo do motor e do contrato.'
  end
end
