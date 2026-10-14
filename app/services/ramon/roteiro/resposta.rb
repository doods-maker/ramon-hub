# Resposta de um passo do roteiro: normaliza o que a IA informa para o tipo do passo e casa com o "quando" das
# saídas (spec 2026-10-13 §3.1). Formato que não serve volta como erro para a IA — nada é gravado.
module Ramon::Roteiro::Resposta
  FAIXA = /\A(<=|>=|<|>)\s*(-?\d+(?:[.,]\d+)?)\z/

  module_function

  # @return [valor_normalizado, erro]
  def normalizar(passo, valor)
    texto = valor.to_s.strip
    return [nil, nil] if texto.empty?

    converter(passo, texto)
  end

  def converter(passo, texto)
    case passo.tipo_resposta
    when 'sim_nao' then exigir(Ramon::Roteiro::Calculadoras.sim_nao(texto), 'Responda sim ou nao.')
    when 'escolha' then exigir(opcao(passo, texto), "Use uma das opcoes: #{Array(passo.opcoes).join(' | ')}.")
    when 'numero' then exigir(Ramon::Roteiro::Calculadoras.numero(texto)&.to_s('F'), 'Informe um numero.')
    when 'data' then exigir(Ramon::Roteiro::Calculadoras.data(texto)&.iso8601, 'Informe a data como AAAA-MM-DD.')
    else [texto, nil]
    end
  end

  def casa?(quando, valor)
    regra = quando.to_s.strip
    return true if regra == '*'

    faixa = FAIXA.match(regra)
    return normal(regra) == normal(valor) if faixa.nil?

    numero = Ramon::Roteiro::Calculadoras.numero(valor)
    !numero.nil? && numero.public_send(faixa[1], BigDecimal(faixa[2].tr(',', '.')))
  end

  def opcao(passo, texto)
    Array(passo.opcoes).find { |o| normal(o) == normal(texto) }
  end

  def exigir(valor, erro)
    valor.nil? ? [nil, erro] : [valor, nil]
  end

  def normal(texto)
    I18n.transliterate(texto.to_s).downcase.strip
  end
end
