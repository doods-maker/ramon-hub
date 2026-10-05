# Passos de decisão do fluxo: `se` (lista de condições com E/OU) e `escolha`
# (uma saída por valor + "outro"). Compara sem acento e sem caixa.
module Ramon::Fluxos::Condicao
  module_function

  def avaliar(config, dados)
    resultados = Array(config['condicoes']).map { |c| teste(c, dados) }
    config['juncao'] == 'ou' ? resultados.any? : resultados.all?
  end

  def escolher(config, dados)
    atual = valores(dados[config['campo']])
    caso = Array(config['casos']).find { |c| Array(c['valores']).any? { |v| atual.include?(normal(v)) } }
    caso ? caso['chave'] : 'outro'
  end

  def teste(condicao, dados) # rubocop:disable Metrics/CyclomaticComplexity
    atual = dados[condicao['campo']]
    esperado = condicao['valor']
    case condicao['operador']
    when 'igual' then valores(atual).include?(normal(esperado))
    when 'diferente' then valores(atual).exclude?(normal(esperado))
    when 'contem' then valores(atual).any? { |v| v.include?(normal(esperado)) }
    when 'nao_contem' then valores(atual).none? { |v| v.include?(normal(esperado)) }
    when 'maior' then atual.present? && atual.to_f > esperado.to_f
    when 'menor' then atual.present? && atual.to_f < esperado.to_f
    when 'existe' then atual.present?
    when 'vazio' then atual.blank?
    when 'em_horario_comercial' then Ramon::Fluxos::Horario.comercial?(Time.current)
    else false
    end
  end

  def valores(atual) = Array(atual).map { |v| normal(v) }

  def normal(valor) = I18n.transliterate(valor.to_s).downcase.strip
end
