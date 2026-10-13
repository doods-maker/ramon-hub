# Salário mínimo nacional por ano — único lugar do valor (honorário, calculadoras do roteiro).
# ponytail: tabela no código; atualizar todo janeiro (checklist de jan/2027 junto com as LPs).
# Ano sem valor cadastrado usa o último conhecido.
module Ramon::SalarioMinimo
  VALORES = { 2026 => BigDecimal('1621.00') }.freeze # Decreto 12.797/2025

  module_function

  def vigente(data = Date.current)
    ano = VALORES.keys.select { |a| a <= data.year }.max || VALORES.keys.min
    VALORES[ano]
  end
end
