# Arquiva o pacote protocolado (PDFs numerados + comprovante) na pasta do cliente no Drive.
# Falha no meio: nada local é apagado e `arquivada_em` não é gravada; o retry pula o que já subiu (drive_file_id).
class Ramon::PeticaoArquivarJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: 15.minutes, attempts: 8

  def perform(peticao_id)
    peticao = Peticao.find(peticao_id)
    return if !Ramon::DriveClient.configured? || !peticao.protocolada? || peticao.arquivada_em.present?

    pasta = pasta_do_pacote(peticao)
    peticao.arquivos.where(drive_file_id: nil).to_a.each { |a| subir_arquivo(a, pasta) }
    subir_comprovante(peticao, pasta)

    peticao.update!(arquivada_em: Time.current)
    peticao.arquivos.each { |a| a.file.purge }
  end

  private

  def pasta_do_pacote(peticao)
    return peticao.drive_pasta_id if peticao.drive_pasta_id.present?

    protocolos = if peticao.drive_pasta_base_id.present?
                   Ramon::DriveClient.ensure_folder('Protocolos', peticao.drive_pasta_base_id)
                 else
                   Ramon::DriveClient.ensure_folder('Protocolos sem cliente', Ramon::DriveClient.root_id)
                 end
    data = peticao.protocolada_em.in_time_zone(Peticao::ZONA).to_date.iso8601
    # (#id) no fim: duas petições do mesmo processo (ou duas iniciais) no mesmo dia não caem na mesma pasta.
    pasta = Ramon::DriveClient.ensure_folder("#{data} — #{peticao.numero_processo.presence || 'Inicial'} (##{peticao.id})", protocolos)
    peticao.update_columns(drive_pasta_id: pasta) # rubocop:disable Rails/SkipsModelValidations
    pasta
  end

  def subir_arquivo(arquivo, pasta)
    id = arquivo.file.open do |io|
      Ramon::DriveClient.upload(name: arquivo.nome_numerado, io: io, content_type: 'application/pdf', parent_id: pasta)
    end
    arquivo.update_columns(drive_file_id: id) # rubocop:disable Rails/SkipsModelValidations
  end

  # ponytail: sem marcador próprio — se o job morrer entre este upload e `arquivada_em`, o retry sobe o comprovante de novo (aceito).
  def subir_comprovante(peticao, pasta)
    return unless peticao.comprovante.attached?

    blob = peticao.comprovante.blob
    blob.open do |io|
      Ramon::DriveClient.upload(name: "Comprovante — evento #{peticao.numero_evento}#{blob.filename.extension_with_delimiter}",
                                io: io, content_type: blob.content_type, parent_id: pasta)
    end
  end
end
