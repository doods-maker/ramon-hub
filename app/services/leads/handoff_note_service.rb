class Leads::HandoffNoteService
  DOSSIER_PREFIX = '📋 DOSSIÊ'.freeze
  MAX_BODY = 1000
  DUPLICATE_WINDOW = 5.minutes

  def initialize(lead:)
    @lead = lead
  end

  def perform
    return if recent_dossier?

    @lead.lead_notes.create!(account: @lead.account, user: nil, body: body)
  end

  private

  def recent_dossier?
    @lead.lead_notes
         .where('body LIKE ?', "#{DOSSIER_PREFIX}%")
         .where(created_at: DUPLICATE_WINDOW.ago..)
         .exists?
  end

  def body
    sections = [header_lines, document_section, [stage_line], notes_section]
    sections.flatten.join("\n").truncate(MAX_BODY, omission: '…')
  end

  def header_lines
    [
      '📋 DOSSIÊ DE PASSAGEM (rascunho — revisar antes de enviar ao jurídico)',
      "Tese: #{thesis_label}",
      "Origem: #{dash(@lead.source)} · Valor: #{value_label} · Prioridade: #{dash(@lead.lead_priority&.name)}",
      "Telefone: #{dash(@lead.contact&.phone_number)}"
    ]
  end

  def document_section
    ['Documentos (tese):', *document_lines]
  end

  def document_lines
    items = @lead.thesis&.thesis_items&.where(section: 'documento').to_a
    return ['• —'] if items.blank?

    items.map { |item| "• #{item.content} [#{doc_status(item)}]" }
  end

  def doc_status(item)
    statuses = @lead.custom_attributes&.dig('doc_status') || {}
    statuses[item.id.to_s].presence || 'pendente'
  end

  def stage_line
    created = @lead.created_at
    days = (@lead.won_at.to_date - created.to_date).to_i
    "Etapas: criado #{created.strftime('%d/%m')} → ganho #{@lead.won_at.strftime('%d/%m')} (#{days} dias)"
  end

  def notes_section
    notes = @lead.lead_notes.where.not('body LIKE ?', "#{DOSSIER_PREFIX}%").last(2)
    return ['Últimas notas: —'] if notes.blank?

    ['Últimas notas:', *notes.map { |note| "• #{note.body.truncate(80)}" }]
  end

  def thesis_label
    @lead.thesis&.name || @lead.benefit_type&.name || '—'
  end

  def value_label
    @lead.value.present? ? "R$ #{@lead.value}" : '—'
  end

  def dash(value)
    value.presence || '—'
  end
end
