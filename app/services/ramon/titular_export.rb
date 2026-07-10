# Export LGPD (art. 18 — direito de acesso do titular): JSON completo com
# dados cadastrais, leads (atividades/notas/tarefas/triagens), notas do
# contato e conversas com mensagens. Consumido pelo TitularExportsController.
class Ramon::TitularExport
  def initialize(contact)
    @contact = contact
  end

  def payload
    {
      gerado_em: Time.zone.now.iso8601,
      titular: @contact.as_json.merge(avatar_url: @contact.avatar_url),
      leads: leads,
      notas: @contact.notes.map { |note| note_json(note) },
      conversas: conversas
    }
  end

  private

  def leads
    @contact.leads
            .includes(:lead_stage, :thesis, :benefit_type, :lead_activities, :lead_notes, :lead_tasks, :lead_triages)
            .map { |lead| lead_json(lead) }
  end

  def lead_json(lead)
    lead.as_json.merge(
      etapa: lead.lead_stage&.name,
      tese: lead.thesis&.name,
      beneficio: lead.benefit_type&.name,
      atividades: lead.lead_activities.as_json,
      notas: lead.lead_notes.as_json,
      tarefas: lead.lead_tasks.as_json,
      triagens: lead.lead_triages.as_json
    )
  end

  def note_json(note)
    { id: note.id, conteudo: note.content, autor: note.user&.name, criado_em: note.created_at }
  end

  def conversas
    @contact.conversations.includes(:inbox, messages: :sender).map do |conversation|
      {
        id: conversation.display_id,
        inbox: conversation.inbox&.name,
        status: conversation.status,
        criado_em: conversation.created_at,
        mensagens: conversation.messages.map { |message| message_json(message) }
      }
    end
  end

  def message_json(message)
    {
      id: message.id,
      tipo: message.message_type,
      privado: message.private,
      autor: message.sender&.name,
      conteudo: message.content,
      criado_em: message.created_at
    }
  end
end
