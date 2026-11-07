require 'prawn'

# Export incremental do checklist pro Drive (ADR-0002). Idempotente: o que já
# está em custom_attributes['drive']['itens'] nunca re-sobe; job pode re-rodar.
class Ramon::DriveExportService
  # Documento que serve a qualquer caso do cliente vai para `00 Pessoais` (grupos 03–05 da skill organizar-documentos-cliente).
  PESSOAL = /\b(RG|CPF|CNH|identidade|resid[eê]ncia|CNIS|CTPS)\b/i
  PASTA_PESSOAIS = '00 Pessoais'.freeze
  COMPLETO = ' — COMPLETO'.freeze # sufixo da pasta do caso quando o checklist fecha (concluir)

  def initialize(lead)
    @lead = lead
  end

  def perform
    return unless Ramon::DriveClient.configured?
    return if @lead.won_at.blank? || @lead.thesis_id.blank?

    pendentes_de_export.each { |item, attachment| exportar(item, attachment) }
    concluir if checklist_completo? && drive_state['concluido_em'].blank?
  end

  # Público: o agente do hub também sobe arquivo avulso na pasta do cliente.
  def pasta_cliente_id
    @pasta_cliente_id ||= drive_state['pasta_id'].presence || begin
      clientes = Ramon::DriveClient.ensure_folder('Clientes', Ramon::DriveClient.root_id)
      id = Ramon::DriveClient.ensure_folder(nome_pasta_cliente, clientes)
      merge_drive('pasta_id' => id)
      id
    end
  end

  # Pasta do caso: `<tese> – MM.AA` (mês do ganho) dentro do cliente; lead sem tese ou não ganho → pasta do cliente.
  # ponytail: trocar a tese depois do ganho não move a pasta (o id fica salvo); mover à mão se acontecer.
  def pasta_tese_id
    return pasta_cliente_id if @lead.thesis.blank? || @lead.won_at.blank?

    @pasta_tese_id ||= drive_state['tese_pasta_id'].presence || begin
      id = Ramon::DriveClient.ensure_folder(nome_tese, pasta_cliente_id)
      merge_drive('tese_pasta_id' => id)
      id
    end
  end

  # Onde a pasta do caso fica depois do concluir, para quem a procura pelo caminho (tarefas no ADVBOX, Recepção da esteira).
  def caminho_completo = "Clientes\\#{nome_pasta_cliente}\\#{nome_tese}#{COMPLETO}\\"

  def nome_pasta_cliente = [nome_cliente, @lead.contact&.cpf.presence].compact.join(' — ')

  def nome_tese = "#{@lead.thesis.name.delete('/\:*?"<>|').squish} – #{@lead.won_at.in_time_zone.strftime('%m.%y')}"

  def nome_cliente
    @nome_cliente ||= (@lead.contact&.name.presence || @lead.name).to_s.strip
  end

  private

  def drive_state = @lead.custom_attributes&.dig('drive') || {}

  def doc_anexos = @lead.custom_attributes&.dig('doc_anexos') || {}

  def pendentes_de_export
    status = @lead.custom_attributes&.dig('doc_status') || {}
    exportados = drive_state['itens'] || {}
    @lead.thesis.thesis_items.where(section: 'documento').filter_map do |item|
      next unless exportavel?(item, status, exportados)

      attachment = Attachment.find_by(id: doc_anexos[item.id.to_s], account_id: @lead.account_id)
      attachment && [item, attachment]
    end
  end

  def exportavel?(item, status, exportados)
    key = item.id.to_s
    status[key] == 'recebido' && doc_anexos[key].present? && exportados[key].blank?
  end

  def exportar(item, attachment)
    @lead.reload # recheck contra estado fresco: outro job pode ter subido este item desde a listagem
    # ponytail: ainda cabe corrida na janela de segundos entre 2 jobs quase simultâneos — lock por lead se aparecer na prática
    return if drive_state.dig('itens', item.id.to_s).present?

    nome_item = item.title.presence || item.content.truncate(60)
    pdf_io, content_type, ext = to_pdf(attachment)
    file_id = Ramon::DriveClient.upload(name: "#{nome_item} — #{nome_cliente}#{ext}", io: pdf_io,
                                        content_type: content_type, parent_id: pasta_destino(nome_item))
    Ramon::DriveClient.shortcut(target_id: file_id, name: "#{nome_cliente} — #{nome_item}#{ext}",
                                parent_id: pasta_do_dia_id)
    merge_drive('itens' => (drive_state['itens'] || {}).merge(item.id.to_s => file_id))
  end

  # jpg/png viram PDF de 1 página via prawn; PDF passa direto; heic/etc sobem
  # no formato original. ponytail: conversão além disso só se aparecer na prática;
  # imagem corrompida levanta e o job morre sem retry — tratar se aparecer na prática.
  def to_pdf(attachment)
    bytes = attachment.file.blob.open(&:read)
    case attachment.file.content_type
    when 'application/pdf'
      [StringIO.new(bytes), 'application/pdf', '.pdf']
    when 'image/jpeg', 'image/jpg', 'image/png'
      doc = Prawn::Document.new(page_size: 'A4', margin: 24)
      doc.image StringIO.new(bytes), fit: [doc.bounds.width, doc.bounds.height]
      [StringIO.new(doc.render), 'application/pdf', '.pdf']
    else
      ext = File.extname(attachment.file.filename.to_s)
      [StringIO.new(bytes), attachment.file.content_type, ext]
    end
  end

  def pasta_destino(nome_item)
    nome_item.match?(PESSOAL) ? Ramon::DriveClient.ensure_folder(PASTA_PESSOAIS, pasta_cliente_id) : pasta_tese_id
  end

  def pasta_do_dia_id
    @pasta_do_dia_id ||= begin
      raiz = Ramon::DriveClient.ensure_folder('A enviar ao ADVBOX', Ramon::DriveClient.root_id)
      Ramon::DriveClient.ensure_folder(Time.zone.today.iso8601, raiz)
    end
  end

  def checklist_completo?
    docs = @lead.docs_counts
    docs[:total].positive? && docs[:received] >= docs[:total]
  end

  def concluir
    # Marca a pasta do caso, não a do cliente: o nome do cliente fica estável para quem a acha pelo nome (portal).
    Ramon::DriveClient.rename(pasta_tese_id, "#{nome_tese}#{COMPLETO}")
    Ramon::AdvboxDocsTaskService.new(@lead).perform
    merge_drive('concluido_em' => Time.zone.now.iso8601)
  end

  def merge_drive(patch)
    @lead.reload # padrão advbox_closing: merge só da chave 'drive' sobre estado fresco
    @lead.update!(custom_attributes: @lead.custom_attributes.to_h.merge(
      'drive' => drive_state.merge(patch)
    ))
  end
end
