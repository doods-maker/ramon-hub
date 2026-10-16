# Feriados que tiram o dia da oferta de horários. Nacionais fixos + móveis datados (acrescentar a cada ano).
module Ramon::Agenda::Feriados
  module_function

  NACIONAIS = [[1, 1], [4, 21], [5, 1], [9, 7], [10, 12], [11, 2], [11, 15], [11, 20], [12, 25]].freeze
  MOVEIS = %w[2026-02-16 2026-02-17 2026-04-03 2026-06-04 2027-02-08 2027-02-09 2027-03-26 2027-05-27].map { |d| Date.iso8601(d) }.freeze
  # ponytail: Tubarão/SC — Eduardo informa as datas; ano novo = acrescentar móveis
  MUNICIPAIS = [].freeze

  def feriado?(date)
    NACIONAIS.include?([date.month, date.day]) || MOVEIS.include?(date) || MUNICIPAIS.include?(date)
  end
end
