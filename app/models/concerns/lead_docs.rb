# Checklist de documentos do lead (badge do card + visão Pós-venda).
# Extraído do Lead pra caber no Metrics/ClassLength (mesmo precedente do LeadCadence).
module LeadDocs
  extend ActiveSupport::Concern

  # Contagem do checklist de documentos.
  # Loaded-aware: o índice do Kanban precarrega thesis_items — sem query por lead.
  def docs_counts
    return { received: 0, total: 0 } if thesis.nil?

    items = doc_items
    status = custom_attributes&.dig('doc_status') || {}
    { received: items.count { |i| status[i.id.to_s] == 'recebido' }, total: items.size }
  end

  private

  def doc_items
    if thesis.association(:thesis_items).loaded?
      thesis.thesis_items.select { |i| i.section == 'documento' }
    else
      thesis.thesis_items.where(section: 'documento').to_a
    end
  end
end
