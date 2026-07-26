# Leitura: roda o motor de calculos (/incapacidade) para o caso, com o mesmo
# payload do Simulador da Sala de Fechamento — CNIS anexado quando existe,
# senao 12 competencias do salario informado.
class Captain::Tools::CalcularBeneficioTool < Captain::Tools::RamonBaseTool
  description 'Calcula no motor o valor do beneficio do caso: renda mensal, valor de hoje e a estimativa de ' \
              'atrasados ate hoje. Usa o CNIS anexado ao caso quando houver; sem CNIS, precisa do salario medio. ' \
              'E estimativa de conversa: nunca prometa esse resultado ao cliente.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :der, type: 'string', desc: 'Data de entrada do requerimento, AAAA-MM-DD. Sem ela, usa a data de hoje.', required: false
  param :salario, type: 'string', desc: 'Salario mensal medio em reais. So e usado quando o caso nao tem CNIS anexado.',
                  required: false
  param :beneficio, type: 'string', desc: "Especie: 'acidente' (auxilio-acidente), 'temporaria' (auxilio-doenca) " \
                                          "ou 'permanente' (invalidez). Sem ela, deduz pela tese do caso.", required: false

  MESES_MEDIA = 12

  def perform(tool_context, lead_id: nil, der: nil, salario: nil, beneficio: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    data = data_iso(der) || Time.zone.today
    faltando = validar(lead, salario)
    return faltando if faltando.present?

    log_tool_usage('calcular_beneficio', { lead_id: lead.id, der: data.iso8601, com_cnis: cnis?(lead) })
    responder(lead, ::Ramon::MotorClient.incapacidade(payload(lead, data, salario, beneficio)), data)
  rescue ::Ramon::MotorClient::ValidationError => e
    "O motor recusou o calculo: #{e.message}"
  rescue ::Ramon::MotorClient::UnavailableError
    MOTOR_FORA
  end

  private

  def cnis?(lead)
    lead.cnis.present?
  end

  # Sem CNIS o motor precisa de salario e de data de nascimento; sem um dos
  # dois a conta nao existe — melhor dizer o que falta do que chutar.
  def validar(lead, salario)
    return nil if cnis?(lead)
    return 'Este caso nao tem CNIS anexado. Informe o salario medio mensal para eu estimar.' if salario.to_f <= 0
    return nil if lead.contact&.data_nascimento.present?

    'Este caso nao tem CNIS nem data de nascimento no cadastro. Sem um dos dois nao da para calcular.'
  end

  def payload(lead, der, salario, beneficio)
    {
      segurado: segurado(lead),
      der: der.iso8601,
      competencias: competencias(lead, der, salario),
      beneficio: especie(lead, beneficio),
      origem: 'previdenciaria',
      acrescimo_25: false,
      memoria_calculo: false
    }
  end

  def segurado(lead)
    return lead.cnis.dig('entrada', 'segurado') if cnis?(lead)

    { nascimento: lead.contact.data_nascimento.iso8601, sexo: lead.contact.sexo.presence || 'M' }
  end

  # ponytail: mesma estimativa do Simulador — salario repetido nas 12
  # competencias anteriores a DER. Com CNIS anexado o historico real entra no lugar.
  def competencias(lead, der, salario)
    return lead.cnis.dig('entrada', 'competencias') if cnis?(lead)

    valor = format('%.2f', salario.to_f)
    (1..MESES_MEDIA).map do |n|
      mes = der << (MESES_MEDIA + 1 - n)
      { ano: mes.year, mes: mes.month, salario: valor }
    end
  end

  # Espelha o guessBeneficio do Simulador: a tese do caso ja diz a especie.
  def especie(lead, beneficio)
    return beneficio if %w[acidente temporaria permanente].include?(beneficio)

    nome = lead.thesis&.name.to_s.downcase
    return 'acidente' if nome.include?('acidente')
    return 'permanente' if nome.include?('permanente') || nome.include?('invalidez')

    'temporaria'
  end

  def responder(lead, resultado, der)
    mensal = resultado['valor_hoje'].presence || resultado['rmi']
    meses = meses_desde(der)
    {
      lead_id: lead.id, nome: lead.name, der: der.iso8601, fonte: cnis?(lead) ? 'CNIS anexado' : 'salario informado',
      renda_mensal_inicial: resultado['rmi'], valor_mensal_hoje: resultado['valor_hoje'],
      meses_desde_a_der: meses, atrasados_estimados: (mensal.to_f * meses).round(2),
      avisos: resultado['avisos'] || [],
      observacao: 'Atrasados sao estimativa (mensal de hoje x meses desde a DER). O honorario fica no Simulador do caso.'
    }.to_json
  end

  def meses_desde(der)
    hoje = Time.zone.today
    [((hoje.year - der.year) * 12) + (hoje.month - der.month), 0].max
  end
end
