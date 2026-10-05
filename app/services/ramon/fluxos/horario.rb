# Horário comercial do escritório para fluxos (condição e "esperar até o horário comercial").
# ponytail: seg–sex 8h–18h fixo; ler do working_hours da caixa se a banca pedir horário por caixa.
module Ramon::Fluxos::Horario
  ZONA = 'America/Sao_Paulo'.freeze
  INICIO = 8
  FIM = 18

  module_function

  def comercial?(momento)
    local = momento.in_time_zone(ZONA)
    (1..5).cover?(local.wday) && local.hour >= INICIO && local.hour < FIM
  end

  def proximo(momento)
    return momento if comercial?(momento)

    local = momento.in_time_zone(ZONA)
    dia = local.hour < INICIO ? local.to_date : local.to_date + 1
    dia += 1 until (1..5).cover?(dia.wday)
    Time.find_zone!(ZONA).local(dia.year, dia.month, dia.day, INICIO)
  end
end
