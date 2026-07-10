# frozen_string_literal: true

# Dossiê de 30 segundos (Sala de Fechamento): agrega em UMA resposta tudo que se
# sabe do lead — pessoa, atribuição, triagem, tese/honorário/objeções, timeline
# e pendências — pro closer ler antes/durante a reunião de fechamento.
class Ramon::DossieService
  TIMELINE_LIMIT = 10

  def initialize(lead:)
    @lead = lead
    @contact = lead.contact
    @thesis = lead.thesis
  end

  def perform
    {
      pessoa: pessoa_block,
      origem: origem_block,
      triagem: triagem_block,
      tese: tese_block,
      timeline: timeline_block,
      pendencias: { tasks: open_tasks, docs_missing: docs_missing }
    }
  end

  private

  def pessoa_block
    {
      lead_id: @lead.id,
      lead_name: @lead.name,
      stage_name: @lead.lead_stage&.name,
      stage_color: @lead.lead_stage&.color,
      value: @lead.value&.to_f,
      conversation_id: @lead.conversation_id
    }.merge(contact_fields)
  end

  def contact_fields
    return %i[contact_id contact_name phone_number idade cidade consent_marketing].index_with { nil } if @contact.blank?

    {
      contact_id: @contact.id,
      contact_name: @contact.name,
      phone_number: @contact.phone_number,
      idade: idade,
      cidade: @contact.additional_attributes&.dig('city'),
      consent_marketing: @contact.custom_attributes&.dig('consent_marketing')
    }
  end

  def idade
    born = @contact&.data_nascimento
    return nil if born.blank?

    today = Time.zone.today
    age = today.year - born.year
    age -= 1 if ([today.month, today.day] <=> [born.month, born.day]).negative?
    age
  end

  def origem_block
    {
      source: @lead.source,
      channel: @lead.channel,
      channel_label: Ramon::SourceCatalog.labels[@lead.channel],
      utm: @lead.custom_attributes&.dig('utm') || {},
      indicacao: @lead.channel == 'indicacao'
    }
  end

  def triagem_block
    triage = @lead.latest_triage
    return nil if triage.blank?

    {
      id: triage.id,
      status: triage.status,
      viability: triage.viability,
      # status awaiting_human (handoff por confiança, PR #48) ou triagem antiga
      # concluída sem viabilidade detectada = precisa de olho humano
      awaiting_human: triage.status == 'awaiting_human' || (triage.status == 'done' && triage.viability.blank?),
      result: triage.result,
      error_message: triage.error_message,
      finished_at: triage.finished_at,
      created_at: triage.created_at
    }
  end

  def tese_block
    return nil if @thesis.blank?

    {
      id: @thesis.id,
      name: @thesis.name,
      honorario_text: honorario_text,
      objecoes: thesis_items_by_section('objecao').map { |i| { title: i.title, content: i.content } }
    }
  end

  # "30% dos atrasados + 3 mensalidades" — fórmula única da casa, varia % e N por tese.
  def honorario_text
    pct = @thesis.honorario_percentual
    return nil if pct.blank?

    pct_text = (pct % 1).zero? ? pct.to_i.to_s : pct.to_f.to_s.tr('.', ',')
    text = "#{pct_text}% dos atrasados"
    n = @thesis.honorario_n_mensalidades.to_i
    return text unless n.positive?

    palavra = n == 1 ? 'mensalidade' : 'mensalidades'
    "#{text} + #{n} #{palavra}"
  end

  def thesis_items_by_section(section)
    @thesis.thesis_items.select { |item| item.section == section }
  end

  def timeline_block
    activities = @lead.lead_activities.includes(:user)
                      .reorder(created_at: :desc, id: :desc).limit(TIMELINE_LIMIT)
    notes = @lead.lead_notes.includes(:user)
                 .reorder(created_at: :desc, id: :desc).limit(TIMELINE_LIMIT)
    items = activities.map { |a| activity_item(a) } + notes.map { |n| note_item(n) }
    items.sort_by { |item| item[:created_at] }.reverse.first(TIMELINE_LIMIT)
  end

  def activity_item(activity)
    {
      type: 'activity',
      kind: activity.kind,
      from_value: activity.from_value,
      to_value: activity.to_value,
      author_name: activity.user&.name,
      created_at: activity.created_at
    }
  end

  def note_item(note)
    { type: 'note', body: note.body, author_name: note.user&.name, created_at: note.created_at }
  end

  def open_tasks
    @lead.lead_tasks.open_tasks.order(:due_at).map do |task|
      { id: task.id, title: task.title, kind: task.kind, due_at: task.due_at }
    end
  end

  # Reusa o dado do DocChecklist: itens 'documento' da tese × custom_attributes.doc_status.
  def docs_missing
    return [] if @thesis.blank?

    status_map = @lead.custom_attributes&.dig('doc_status') || {}
    thesis_items_by_section('documento').filter_map { |item| missing_doc(item, status_map) }
  end

  def missing_doc(item, status_map)
    status = status_map[item.id.to_s].presence || 'pendente'
    return if status == 'recebido'

    { title: item.title.presence || item.content, status: status }
  end
end
