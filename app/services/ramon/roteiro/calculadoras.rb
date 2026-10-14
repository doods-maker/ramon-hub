# Contas exatas do roteiro da tese (spec 2026-10-13 §3.3). Cada uma recebe os campos já respondidos — como o motor
# grava: 'sim'/'nao', datas ISO, números em texto — e devolve { resultado:, detalhe: }. Campo faltando = 'depende'
# (a saída configurada no passo decide; normalmente equipe).
module Ramon::Roteiro::Calculadoras # rubocop:disable Metrics/ModuleLength -- 7 contas + catálogo; separar não ajuda a leitura
  # Campos que cada conta lê e resultados que devolve: a tela do roteiro (F2) mostra e a Conferencia valida.
  CATALOGO = {
    'periodo_de_graca' => { campos: %w[ultimo_vinculo evento mais_de_120 desemprego facultativa], resultados: %w[dentro fora depende] },
    'renda_per_capita' => { campos: %w[renda_total moradores], resultados: %w[abaixo acima depende] },
    'prescricao_5_anos' => { campos: %w[data], resultados: %w[dentro ultimo_ano prescrito depende] },
    'prescricao_2_anos' => { campos: %w[saida], resultados: %w[dentro ultimos_meses prescrito depende] },
    'meses_ate_65' => { campos: %w[nascimento], resultados: %w[ja_tem_65 menos_de_65 depende] },
    'data_prevista_parto' => { campos: %w[semanas], resultados: %w[ja_pode_pedir aguardar depende] },
    'prazo_inss' => { campos: %w[requerimento pericia], resultados: %w[aguardar forcar_julgamento depende] }
  }.freeze
  NOMES = CATALOGO.keys.freeze
  DEPENDE = { resultado: 'depende', detalhe: 'falta dado para a conta' }.freeze

  module_function

  def calcular(nome, campos, hoje: Date.current)
    return DEPENDE unless NOMES.include?(nome.to_s)

    send(nome, (campos || {}).to_h.transform_keys(&:to_s), hoje)
  end

  # Lei 8.213 art. 15: 12 meses depois do último vínculo (II); +12 com mais de 120 contribuições (§1º); +12 com
  # desemprego comprovado (§2º); facultativo, 6 meses (VI). §4º + Decreto 3.048 art. 14: a qualidade vai até o
  # dia 15 do 2º mês seguinte ao fim do prazo.
  # Campos: ultimo_vinculo, evento (datas); mais_de_120, desemprego, facultativa (sim/nao; vazio = não sabe).
  def periodo_de_graca(campos, _hoje)
    fim = data(campos['ultimo_vinculo'])
    evento = data(campos['evento'])
    return DEPENDE unless fim && evento
    return res('dentro', 'tinha vínculo na data do evento') if evento <= fim
    return graca_facultativa(fim, evento) if sim_nao(campos['facultativa']) == 'sim'

    meses = [12, 24, 36].find { |m| evento <= mantem_ate(fim, m) }
    return res('fora', 'mais de 36 meses sem contribuir') if meses.nil?

    graca_estendida(meses, campos['mais_de_120'], campos['desemprego'])
  end

  def mantem_ate(fim, meses)
    limite = fim >> (meses + 2)
    Date.new(limite.year, limite.month, 15)
  end

  def graca_facultativa(fim, evento)
    return res('dentro', 'facultativa: dentro dos 6 meses') if evento <= mantem_ate(fim, 6)

    res('fora', 'facultativa: mais de 6 meses sem contribuir')
  end

  # Quantas extensões o prazo precisa (24 meses = 1, 36 = 2) e quantas a pessoa tem ('sim'); vazio = talvez.
  def graca_estendida(meses, mais_de_120, desemprego)
    precisa = (meses - 12) / 12
    respostas = [mais_de_120, desemprego].map { |v| sim_nao(v) }
    tem = respostas.count('sim')
    return res('dentro', "dentro dos #{meses} meses de graça") if tem >= precisa
    return res('fora', "precisaria de #{meses} meses de graça") if tem + respostas.count(nil) < precisa

    res('depende', 'depende das 120 contribuições ou do desemprego comprovado')
  end

  # Lei 8.742 art. 20 §3º: renda por pessoa igual ou inferior a ¼ do salário mínimo.
  def renda_per_capita(campos, hoje)
    renda = numero(campos['renda_total'])
    moradores = numero(campos['moradores'])
    return DEPENDE unless renda && moradores&.positive?

    por_pessoa = (renda / moradores).round(2)
    limite = (Ramon::SalarioMinimo.vigente(hoje) / 4).round(2)
    detalhe = "R$ #{por_pessoa.to_s('F')} por pessoa; limite R$ #{limite.to_s('F')} (1/4 do salário mínimo)"
    res(por_pessoa <= limite ? 'abaixo' : 'acima', detalhe)
  end

  # Parcelas prescrevem em 5 anos (art. 103 parágrafo único); entre 4 e 5 anos = risco, a saída decide.
  def prescricao_5_anos(campos, hoje)
    quando = data(campos['data'])
    return DEPENDE if quando.nil?
    return res('dentro', 'menos de 4 anos') if quando > hoje.prev_year(4)
    return res('ultimo_ano', 'entre 4 e 5 anos') if quando >= hoje.prev_year(5)

    res('prescrito', 'mais de 5 anos')
  end

  # Ação trabalhista até 2 anos depois do fim do contrato (CF art. 7º, XXIX); de 21 a 24 meses = urgente, a saída decide.
  # ponytail: conta da data de saída informada; projeção do aviso prévio fica com a equipe (cai na faixa urgente).
  def prescricao_2_anos(campos, hoje)
    saida = data(campos['saida'])
    return DEPENDE if saida.nil?
    return res('dentro', 'saiu há menos de 21 meses') if saida > hoje.prev_month(21)
    return res('ultimos_meses', "prazo de 2 anos vence em #{saida.next_year(2).strftime('%d/%m/%Y')}") if saida >= hoje.prev_year(2)

    res('prescrito', 'saiu há mais de 2 anos')
  end

  def meses_ate_65(campos, hoje)
    nascimento = data(campos['nascimento'])
    return DEPENDE if nascimento.nil?

    faz65 = nascimento.next_year(65)
    return res('ja_tem_65', "fez 65 em #{faz65.strftime('%d/%m/%Y')}") if hoje >= faz65

    meses = ((faz65.year * 12) + faz65.month) - ((hoje.year * 12) + hoje.month)
    meses -= 1 if faz65.day < hoje.day
    res('menos_de_65', "faltam #{meses} meses para os 65 (#{faz65.strftime('%d/%m/%Y')})")
  end

  # Parto previsto com 40 semanas; o salário-maternidade pode começar 28 dias antes (Lei 8.213, art. 71).
  def data_prevista_parto(campos, hoje)
    semanas = numero(campos['semanas'])
    return DEPENDE unless semanas&.between?(1, 42)

    parto = hoje + ((40 - semanas) * 7).round
    pode_pedir = parto - 28
    detalhe = "parto previsto por volta de #{parto.strftime('%d/%m/%Y')}; pode pedir a partir de #{pode_pedir.strftime('%d/%m/%Y')}"
    res(hoje >= pode_pedir ? 'ja_pode_pedir' : 'aguardar', detalhe)
  end

  # Pedido parado: mais de 45 dias da perícia ou mais de 90 do requerimento → ação para forçar o julgamento.
  def prazo_inss(campos, hoje)
    requerimento = data(campos['requerimento'])
    pericia = data(campos['pericia'])
    return DEPENDE unless requerimento || pericia

    parado = dias_desde(pericia, hoje) > 45 || dias_desde(requerimento, hoje) > 90
    res(parado ? 'forcar_julgamento' : 'aguardar', parado ? 'passou do prazo de análise' : 'ainda no prazo de análise')
  end

  def dias_desde(data, hoje)
    data ? (hoje - data).to_i : 0
  end

  # "R$ 1.200,50", "R$ 1.200", "1200.5" → BigDecimal; vazio ou lixo → nil.
  def numero(valor)
    texto = valor.to_s.gsub(/[^\d,.-]/, '')
    texto = texto.delete('.').tr(',', '.') if texto.include?(',') || texto.match?(/\A-?\d{1,3}(\.\d{3})+\z/)
    texto.empty? ? nil : BigDecimal(texto)
  rescue ArgumentError
    nil
  end

  def data(valor)
    texto = valor.to_s.strip
    return Date.iso8601(texto) if texto.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.strptime(texto, '%d/%m/%Y') if texto.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
  rescue ArgumentError
    nil
  end

  def sim_nao(valor)
    texto = I18n.transliterate(valor.to_s).downcase.gsub(/[^a-z]/, '')
    return 'sim' if %w[sim s].include?(texto)

    'nao' if %w[nao n].include?(texto)
  end

  def res(resultado, detalhe)
    { resultado: resultado, detalhe: detalhe }
  end
end
