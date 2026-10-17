# Horário comercial do escritório (decisão Eduardo 06/10): seg–sex, 8h30–12h00
# e 13h30–18h00, America/Sao_Paulo — o PADRÃO. Dias e faixas podem ser mudados por conta na tela "Como a IA atende"
# (Ramon::IaLimites, account.settings['ia_limites']); sem conta, vale o padrão. Base da 1ª resposta, do "sem resposta há
# +1h" do Painel do time e dos horários livres da Agenda — sem depender do value_in_business_hours do Chatwoot.
# ponytail: feriado fica pra depois (conta como dia útil); somar um calendário
# de feriados aqui quando o painel precisar.
module Ramon::HorarioComercial
  module_function

  TIME_ZONE = 'America/Sao_Paulo'.freeze
  JANELAS = [[[8, 30], [12, 0]], [[13, 30], [18, 0]]].freeze
  DIAS = [1, 2, 3, 4, 5].freeze # Date#wday: 0 = domingo

  # As faixas da conta como [[hora, min], [hora, min]] (conta nil = padrão).
  def janelas(account = nil)
    Ramon::IaLimites.de(account)[:horario]['janelas'].map { |faixa| faixa.map { |hhmm| [hhmm[0, 2].to_i, hhmm[3, 2].to_i] } }
  end

  # Dias da semana (Date#wday) em que o escritório atende.
  def dias(account = nil) = Ramon::IaLimites.de(account)[:horario]['dias']

  # Dia de atendimento e dentro de uma faixa (fim exclusivo), no fuso do escritório.
  def aberto?(momento, account = nil)
    local = momento.in_time_zone(TIME_ZONE)
    return false unless dias(account).include?(local.wday)

    minuto = (local.hour * 60) + local.min
    janelas(account).any? { |(hora_ini, min_ini), (hora_fim, min_fim)| minuto >= (hora_ini * 60) + min_ini && minuto < (hora_fim * 60) + min_fim }
  end

  # Minutos (Float) de [inicio, fim] que caem dentro das faixas.
  def minutos_entre(inicio, fim, account = nil)
    return 0.0 if inicio.blank? || fim.blank? || fim <= inicio

    zona = ActiveSupport::TimeZone[TIME_ZONE]
    ini = inicio.in_time_zone(zona)
    fin = fim.in_time_zone(zona)
    uteis = dias(account)
    faixas = janelas(account)
    (ini.to_date..fin.to_date).sum { |dia| uteis.include?(dia.wday) ? minutos_no_dia(zona, dia, ini, fin, faixas) : 0.0 }
  end

  def minutos_no_dia(zona, dia, ini, fin, faixas)
    faixas.sum do |(hora_ini, min_ini), (hora_fim, min_fim)|
      abre = [zona.local(dia.year, dia.month, dia.day, hora_ini, min_ini), ini].max
      fecha = [zona.local(dia.year, dia.month, dia.day, hora_fim, min_fim), fin].min
      fecha > abre ? (fecha - abre) / 60.0 : 0.0
    end
  end
end
