# Grade de sugestão de horário das peças: ter/qua/qui 12h (BRT) — o time inteiro
# reposta na hora do almoço (decisão do Eduardo 02/10/2026).
module Ramon::GradeConteudo
  # ponytail: grade fixa no código; trocar aqui se as métricas pedirem
  SLOTS = { 2 => [12, 0], 3 => [12, 0], 4 => [12, 0] }.freeze
  FUSO = 'America/Sao_Paulo'.freeze
  OCUPA = %w[agendado publicando publicado].freeze

  module_function

  def proximo_horario(account, agora = Time.current)
    zona = Time.find_zone(FUSO)
    ocupados = account.pecas.where(status: OCUPA).where(agendado_para: agora..).pluck(:agendado_para).to_set(&:to_i)
    hoje = agora.in_time_zone(zona).to_date
    (0..21).each do |d|
      dia = hoje + d
      slot = SLOTS[dia.wday]
      next unless slot

      horario = zona.local(dia.year, dia.month, dia.day, *slot)
      return horario if horario > agora && ocupados.exclude?(horario.to_i)
    end
    nil
  end
end
