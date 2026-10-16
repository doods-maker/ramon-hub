# Reuniao de fechamento conforme o modo da IA: no modo direto (Ramon::CopilotoModo.direto?) marca na agenda do
# Closer, so se o horario passa na regra completa de Disponibilidade (a IA marca o que ela mesma ofereceu);
# nos demais, sugestao pendente — aplicar cria a tarefa na Esteira, e quem confirma a data com o cliente e o humano.
class Captain::Tools::AgendarReuniaoTool < Captain::Tools::RamonEscritaTool
  description 'No modo direto marca a reuniao na agenda; nos demais cria uma sugestao pendente para a equipe confirmar.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :quando, type: 'string', desc: 'Data e hora propostas, no formato AAAA-MM-DD HH:MM', required: true
  param :assunto, type: 'string', desc: 'Assunto da reuniao, em uma linha', required: false

  def perform(tool_context, quando: nil, lead_id: nil, assunto: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    direto = Ramon::CopilotoModo.direto?(lead.copiloto_modo)
    horario = horario_de(quando)
    return "Nao entendi a data (hoje e #{hoje_br}). Use o formato AAAA-MM-DD HH:MM." if horario.blank?
    return "A data proposta ja passou (hoje e #{hoje_br}). Sugira uma data futura." if horario < Time.current

    log_tool_usage('agendar_reuniao', { lead_id: lead.id, quando: horario.iso8601 })
    titulo = assunto.presence || 'Reuniao de fechamento'
    return marcar(lead, horario, titulo) if direto && com_closer?(lead)

    sugerir(lead, acao: 'reuniao', texto: "#{titulo} com #{lead.name} em #{horario.strftime('%d/%m/%Y %H:%M')}",
                  quando: horario.iso8601, titulo: titulo)
  end

  private

  def hoje_br
    Time.current.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')
  end

  def com_closer?(lead)
    Ramon::Papeis.atribuir_closer!(lead)
    lead.closer.present? && GoogleAgendaConta.de(lead.closer).present? # sem Google conectado, só sugere
  end

  # Nenhum HTTP do Google dentro de transacao: livre? (que le o Google) roda antes do call.
  def marcar(lead, horario, titulo)
    return 'Esse horário não está disponível — ofereça um dos Horários livres.' unless
      Ramon::Agenda::Disponibilidade.new(user: lead.closer, account: lead.account).livre?(horario)

    Ramon::ReuniaoAgendamento.call(lead: lead, starts_at: horario, title: titulo, automatico: true)
    aviso = ' A confirmação já foi enviada ao cliente — não repita.' if Ramon::ReuniaoAgendamento.envia_sozinha?(lead)
    "Reunião marcada para #{Ramon::ReuniaoAgendamento.quando(horario)}.#{aviso}"
  end

  # O horario vem em Sao Paulo (de horarios_livres ou do LLM); o Time.zone do app e UTC.
  def horario_de(quando)
    Time.find_zone!(Ramon::HorarioComercial::TIME_ZONE).parse(quando.to_s)
  rescue ArgumentError
    nil
  end
end
