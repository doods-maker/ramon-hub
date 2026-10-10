# Lembrete de audiência/perícia ao cliente, 7 dias e 1 dia antes, pela agenda do espelho (tarefa do ADVBOX com data).
# Textos aprovados pelo Eduardo em 09/10/2026. Sai pelo Ramon::PortalAvisosJob das 8h: e-mail ao cliente que tem e-mail
# e 1 linha no resumo da equipe com o texto pronto de WhatsApp.
# ponytail: sem registro de "já enviado" — o job roda 1x por dia e só casa "faltam exatamente 7 ou 1 dia"; rodar o
# job 2x no mesmo dia manda 2x.
module Ramon::PortalLembretes
  ANTECEDENCIAS = [7, 1].freeze
  DIAS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  TEXTOS = {
    %w[audiencia 7] => 'Sua audiência está marcada para %<dia>s, %<data>s%<hora>s%<formato>s. Nos próximos dias a nossa equipe ' \
                       'vai falar com você para explicar como vai ser e como se preparar. Qualquer dúvida, fale com a gente ' \
                       'pelo WhatsApp %<whatsapp>s.',
    %w[audiencia 1] => 'Lembrete: sua audiência é amanhã, %<data>s%<hora>s%<formato>s. Chegue cedo e leve um documento com foto. ' \
                       'Se tiver dúvida, fale com a equipe pelo WhatsApp %<whatsapp>s.',
    %w[pericia 7] => 'Sua perícia médica está marcada para %<dia>s, %<data>s%<hora>s. Separe documento com foto e todos os ' \
                     'laudos, exames e receitas que tiver. A equipe vai confirmar o local com você.',
    %w[pericia 1] => 'Lembrete: sua perícia é amanhã, %<data>s%<hora>s. Chegue cedo e leve documento com foto, laudos, exames e receitas.'
  }.freeze

  module_function

  # [[processo, { 'titulo', 'corpo' (sem saudação), 'texto' (como vai no e-mail) }]] dos compromissos que vencem
  # daqui a 7 ou 1 dia, só de processos ativos.
  def devidos(cliente, hoje: Date.current)
    cliente.processos.reject { |p| Ramon::PortalTexto.encerrado?(p) }.flat_map do |p|
      Array(p['agenda']).filter_map do |a|
        quando = Time.zone.parse(a['quando'].to_s)
        dias = quando && (quando.to_date - hoje).to_i
        [p, lembrete(cliente, a, quando, dias)] if ANTECEDENCIAS.include?(dias) && TEXTOS.key?([a['tipo'], dias.to_s])
      end
    end
  end

  def lembrete(cliente, agenda, quando, dias)
    corpo = format(TEXTOS[[agenda['tipo'], dias.to_s]], dia: DIAS[quando.wday], data: quando.strftime('%d/%m/%Y'),
                                                        hora: hora(quando), formato: agenda['formato'] ? " (#{agenda['formato']})" : '',
                                                        whatsapp: whatsapp)
    nome = agenda['tipo'] == 'audiencia' ? 'audiência' : 'perícia'
    { 'titulo' => dias == 1 ? "Lembrete: sua #{nome} é amanhã" : "Lembrete: sua #{nome} é no dia #{quando.strftime('%d/%m')}",
      'corpo' => corpo, 'texto' => dias == 1 ? corpo : "Olá, #{cliente.primeiro_nome}. #{corpo}" }
  end

  # 16:00 → ", às 16h"; 09:30 → ", às 9h30"; tarefa sem hora (00:00) → sem horário.
  def hora(quando)
    return '' if quando.strftime('%H:%M') == '00:00'

    ", às #{quando.strftime('%-Hh%M').delete_suffix('00')}"
  end

  # 5548988554077 → (48) 98855-4077
  def whatsapp
    fone = ENV.fetch('PORTAL_WHATSAPP', '5548988554077').delete('^0-9').last(11)
    "(#{fone[0, 2]}) #{fone[2..-5]}-#{fone[-4..]}"
  end
end
