# Checklist de documentos do lead (badge do card + visão Pós-venda).
# Extraído do Lead pra caber no Metrics/ClassLength (mesmo precedente do LeadCadence).
module LeadDocs
  extend ActiveSupport::Concern

  # Perdido: o link mágico do portal (/portal/:token) morre; se o lead reabrir, outro nasce sob demanda.
  # Ganho mantém: o portal segue recebendo os documentos que faltam depois do contrato (Lead#enqueue_drive_export).
  included do
    before_save -> { self.portal_token = nil }, if: -> { will_save_change_to_lead_stage_id? && lead_stage&.is_lost }
    # Desmarcar "recebido" solta o anexo e o vínculo do Drive daquele item (o arquivo no Drive fica: é do cliente).
    before_save :soltar_docs_desmarcados, if: :custom_attributes_changed?
  end

  # Contagem do checklist de documentos.
  # Loaded-aware: o índice do Kanban precarrega thesis_items — sem query por lead.
  def docs_counts
    return { received: 0, total: 0 } if thesis.nil?

    items = doc_items
    status = custom_attributes&.dig('doc_status') || {}
    { received: items.count { |i| status[i.id.to_s] == 'recebido' }, total: items.size }
  end

  # Checklist da tese com o status de cada item (ficha e texto de passagem).
  def doc_checklist
    return [] if thesis.nil?

    status = custom_attributes&.dig('doc_status') || {}
    doc_items.map do |item|
      { id: item.id, title: item.title.presence || item.content, status: status[item.id.to_s].presence || 'pendente' }
    end
  end

  private

  def soltar_docs_desmarcados
    attrs = custom_attributes.to_h.deep_dup
    recebidos = ->(mapa) { mapa.select { |key, _| attrs.dig('doc_status', key.to_s) == 'recebido' } }
    attrs['doc_anexos'] = recebidos.call(attrs['doc_anexos']) if attrs['doc_anexos'].is_a?(Hash)
    itens = attrs.dig('drive', 'itens')
    attrs['drive']['itens'] = recebidos.call(itens) if itens.is_a?(Hash)
    self.custom_attributes = attrs if attrs != custom_attributes.to_h
  end

  def doc_items
    if thesis.association(:thesis_items).loaded?
      thesis.thesis_items.select { |i| i.section == 'documento' }
    else
      thesis.thesis_items.where(section: 'documento').to_a
    end
  end
end
