# Leitura: horarios livres da agenda do Closer do caso (fixa o Closer no lead se faltar). A IA oferece estes
# horarios exatamente como vierem e so depois agenda com agendar_reuniao.
class Captain::Tools::HorariosLivresTool < Captain::Tools::RamonBaseTool
  description 'Horarios livres para a conversa com o advogado nos proximos 5 dias uteis. Use antes de combinar ' \
              'dia e hora com o cliente e ofereca exatamente estes horarios.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false

  SEM_HORARIO = 'Sem horário livre nos próximos 5 dias úteis — passe para a equipe.'.freeze

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    log_tool_usage('horarios_livres', { lead_id: lead.id })
    livres = Ramon::Agenda::Disponibilidade.livres_do_lead(lead)
    return SEM_HORARIO if livres.empty?

    "Horários livres com #{lead.closer.name}: #{Ramon::Agenda::Disponibilidade.texto(livres)}. " \
      'Ofereça estes ao cliente e espere ele escolher.'
  end
end
