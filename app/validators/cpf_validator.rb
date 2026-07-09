# Valida CPF já normalizado (11 dígitos): formato + dígitos verificadores.
class CpfValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    record.errors.add(attribute, options[:message] || :invalid) unless valid_cpf?(value)
  end

  private

  def valid_cpf?(cpf)
    return false unless cpf.match?(/\A\d{11}\z/)
    return false if cpf.chars.uniq.one?

    [9, 10].all? { |len| verifier_digit(cpf, len) == cpf[len].to_i }
  end

  # dv = ((soma dos dígitos * pesos decrescentes) * 10) % 11, com 10 → 0
  def verifier_digit(cpf, len)
    sum = cpf[0, len].chars.each_with_index.sum { |digit, i| digit.to_i * (len + 1 - i) }
    mod = (sum * 10) % 11
    mod == 10 ? 0 : mod
  end
end
