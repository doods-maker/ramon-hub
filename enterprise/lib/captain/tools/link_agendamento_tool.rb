# Leitura pura: o link publico de agendamento (Cal.com) para o lead escolher
# dia e horario. Sem link configurado, o humano combina e registra.
class Captain::Tools::LinkAgendamentoTool < Captain::Tools::BasePublicTool
  description 'Devolve o link de agendamento para o lead escolher dia e horario da reuniao, ' \
              'com uma frase sugerida. Use quando o lead topar conversar com o advogado.'

  SEM_LINK = 'Link de agendamento nao configurado — combine o horario com o lead e registre com agendar_reuniao.'.freeze

  def perform(_tool_context)
    url = ENV.fetch('RAMON_CALCOM_URL', '').strip
    return SEM_LINK if url.blank?

    log_tool_usage('link_agendamento')
    "Link para o lead escolher dia e horario: #{url}. " \
      'Sugestao de frase: "Para a gente conversar com calma, escolha o melhor dia e horario para voce aqui: ' \
      "#{url} — a conversa e sem compromisso.\""
  rescue StandardError => e
    Rails.logger.error("LinkAgendamentoTool: #{e.class}: #{e.message}")
    SEM_LINK
  end
end
