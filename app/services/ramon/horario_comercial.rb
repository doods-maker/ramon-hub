# Horário comercial do escritório (decisão Eduardo 06/10): seg–sex, 8h30–12h00
# e 13h30–18h00, America/Sao_Paulo. Base da 1ª resposta e do "sem resposta há
# +1h" do Painel do time — sem depender do value_in_business_hours do Chatwoot.
# ponytail: feriado fica pra depois (conta como dia útil); somar um calendário
# de feriados aqui quando o painel precisar.
module Ramon::HorarioComercial
  module_function

  TIME_ZONE = 'America/Sao_Paulo'.freeze
  JANELAS = [[[8, 30], [12, 0]], [[13, 30], [18, 0]]].freeze

  # Minutos (Float) de [inicio, fim] que caem dentro das janelas.
  def minutos_entre(inicio, fim)
    return 0.0 if inicio.blank? || fim.blank? || fim <= inicio

    zona = ActiveSupport::TimeZone[TIME_ZONE]
    ini = inicio.in_time_zone(zona)
    fin = fim.in_time_zone(zona)
    (ini.to_date..fin.to_date).sum { |dia| minutos_no_dia(zona, dia, ini, fin) }
  end

  def minutos_no_dia(zona, dia, ini, fin)
    return 0.0 if dia.saturday? || dia.sunday?

    JANELAS.sum do |(hora_ini, min_ini), (hora_fim, min_fim)|
      abre = [zona.local(dia.year, dia.month, dia.day, hora_ini, min_ini), ini].max
      fecha = [zona.local(dia.year, dia.month, dia.day, hora_fim, min_fim), fin].min
      fecha > abre ? (fecha - abre) / 60.0 : 0.0
    end
  end
end
