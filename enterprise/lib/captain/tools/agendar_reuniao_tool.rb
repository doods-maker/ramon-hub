# Escrita com aprovacao: propoe a reuniao de fechamento. Nada e agendado com o
# cliente aqui — aplicar a sugestao cria a tarefa na Esteira, e quem confirma a
# data com o cliente e o humano.
class Captain::Tools::AgendarReuniaoTool < Captain::Tools::RamonEscritaTool
  description 'Prepara o agendamento da reuniao de fechamento do caso. NAO marca nada na agenda do cliente: cria ' \
              'uma sugestao pendente que, aprovada pelo humano, vira tarefa na Esteira com data e hora.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :quando, type: 'string', desc: 'Data e hora propostas, no formato AAAA-MM-DD HH:MM', required: true
  param :assunto, type: 'string', desc: 'Assunto da reuniao, em uma linha', required: false

  def perform(tool_context, quando: nil, lead_id: nil, assunto: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    horario = horario_de(quando)
    return "Nao entendi a data (hoje e #{hoje_br}). Use o formato AAAA-MM-DD HH:MM." if horario.blank?
    return "A data proposta ja passou (hoje e #{hoje_br}). Sugira uma data futura." if horario < Time.current

    log_tool_usage('agendar_reuniao', { lead_id: lead.id, quando: horario.iso8601 })
    titulo = assunto.presence || 'Reuniao de fechamento'
    sugerir(lead, acao: 'reuniao', texto: "#{titulo} com #{lead.name} em #{horario.strftime('%d/%m/%Y %H:%M')}",
                  quando: horario.iso8601, titulo: titulo)
  end

  private

  def hoje_br
    Time.current.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')
  end

  def horario_de(quando)
    Time.zone.parse(quando.to_s)
  rescue ArgumentError
    nil
  end
end
