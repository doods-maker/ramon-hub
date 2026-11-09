# Grava o "00 Atendimento.md" (a colheita em texto) na pasta da tese do cliente, na passagem Documentos → Jurídico, antes da
# ANÁLISE DO CASO. Nunca sobrescreve (nome com a data se já existir) e o retry do job não grava de novo (marca em
# custom_attributes['atendimento_md']). Nunca levanta: falha vira :falhou e linha no histórico; a passagem segue.
module Ramon::Colheita::ArquivoAtendimento
  NOME = '00 Atendimento.md'.freeze

  module_function

  # -> :gravado | :ja_gravado | :sem_drive | :falhou
  def gravar(lead)
    return registrar_sem_drive(lead) unless Ramon::DriveClient.configured?
    return :ja_gravado if ja_gravado?(lead)

    reextrair(lead)
    pasta = Ramon::DriveExportService.new(lead).pasta_tese_id
    id = Ramon::DriveClient.upload(name: nome_livre(pasta), io: StringIO.new(Ramon::Colheita::Atendimento.markdown(lead)),
                                   content_type: 'text/markdown', parent_id: pasta)
    marcar(lead, id)
    Ramon::Documentos::Entrada.registrar(lead, '00 Atendimento.md gravado na pasta da tese')
    :gravado
  rescue StandardError => e
    Rails.logger.warn("[Ramon::Colheita::ArquivoAtendimento] lead #{lead.id}: #{e.class}")
    Ramon::Documentos::Entrada.registrar(lead, "00 Atendimento.md não foi gravado: #{e.class}")
    :falhou
  end

  def registrar_sem_drive(lead)
    Ramon::Documentos::Entrada.registrar(lead, '00 Atendimento.md: Drive não configurado')
    :sem_drive
  end

  # Só grava de novo se a passagem for posterior à última gravação.
  def ja_gravado?(lead)
    em = lead.custom_attributes&.dig('atendimento_md', 'gravado_em')
    return false if em.blank?

    lead.docs_completos_em.blank? || lead.docs_completos_em <= Time.zone.parse(em)
  end

  # Colheita fresca; erro do LLM não impede o arquivo (sai com a colheita que já existe).
  def reextrair(lead)
    Ramon::ColheitaExtractionService.new(lead).perform
    lead.reload
  rescue Ramon::LlmClient::TransientError => e
    Rails.logger.warn("[Ramon::Colheita::ArquivoAtendimento] extração adiada: #{e.class}")
  end

  # ponytail: se o nome com a data também já existir, o Drive aceita duplicado (nada é sobrescrito).
  def nome_livre(pasta)
    existentes = Ramon::DriveClient.conteudo_da_pasta(pasta).pluck(:name)
    return NOME unless existentes.include?(NOME)

    "00 Atendimento (#{Time.current.strftime('%Y-%m-%d')}).md"
  end

  def marcar(lead, file_id)
    lead.reload
    marca = { 'file_id' => file_id, 'gravado_em' => Time.current.iso8601 }
    lead.update!(custom_attributes: (lead.custom_attributes || {}).merge('atendimento_md' => marca))
  end
end
