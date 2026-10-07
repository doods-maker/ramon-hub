# Horário comercial do escritório para fluxos (condição "agora é horário comercial" e "esperar até o horário comercial").
# B4.2: cada passo pode ter a SUA janela — 'dias' (0 = domingo … 6 = sábado), 'inicio' e 'fim' (horas; fim exclusivo,
# 24 = até a meia-noite) no config do passo ou da condição. Sem as chaves = o padrão seg–sex 8h–18h. Fuso de São Paulo.
module Ramon::Fluxos::Horario
  ZONA = 'America/Sao_Paulo'.freeze
  INICIO = 8
  FIM = 18
  DIAS = [1, 2, 3, 4, 5].freeze

  module_function

  # Dia fora de 0–6 é ignorado e lista vazia vira o padrão: o `until` de `proximo` nunca gira à toa.
  def janela(config)
    c = config || {}
    dias = Array(c['dias']).map(&:to_i) & (0..6).to_a
    { dias: dias.presence || DIAS, inicio: (c['inicio'] || INICIO).to_i, fim: (c['fim'] || FIM).to_i }
  end

  # Publicar recusa (Grafo#erros_janela): nenhum dia, dia fora de 0–6, início ≥ fim ou fim > 24.
  def janela_valida?(config)
    dias = config.key?('dias') ? Array(config['dias']).map(&:to_i) : DIAS
    j = janela(config)
    dias.any? && (dias - (0..6).to_a).empty? && (0...j[:fim]).cover?(j[:inicio]) && j[:fim] <= 24
  end

  def comercial?(momento, config = nil)
    j = janela(config)
    local = momento.in_time_zone(ZONA)
    j[:dias].include?(local.wday) && local.hour >= j[:inicio] && local.hour < j[:fim]
  end

  def proximo(momento, config = nil)
    return momento if comercial?(momento, config)

    j = janela(config)
    local = momento.in_time_zone(ZONA)
    dia = local.hour < j[:inicio] ? local.to_date : local.to_date + 1
    dia += 1 until j[:dias].include?(dia.wday)
    Time.find_zone!(ZONA).local(dia.year, dia.month, dia.day, j[:inicio])
  end
end
