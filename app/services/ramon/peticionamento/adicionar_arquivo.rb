require 'prawn'

# Põe um arquivo no pacote da petição: PDF passa; JPG/PNG viram PDF A4 de 1 página; o resto é recusado.
class Ramon::Peticionamento::AdicionarArquivo
  IMAGENS = %w[image/jpeg image/jpg image/png].freeze

  def self.call(...) = new.call(...)

  def call(peticao, bytes:, nome:, content_type:, origem:, drive_origem_id: nil, tipo: nil, principal: false) # rubocop:disable Metrics/ParameterLists
    raise ArgumentError, 'protocolada' unless peticao.editavel?

    pdf = para_pdf(bytes, content_type)
    nome = "#{File.basename(nome.to_s, '.*')}.pdf"
    peticao.transaction do
      peticao.arquivos.update_all(principal: false) if principal # rubocop:disable Rails/SkipsModelValidations
      arquivo = peticao.arquivos.create!(
        nome: nome, tipo: tipo || Ramon::Peticionamento::Tribunais.sugerir_tipo(nome), origem: origem, drive_origem_id: drive_origem_id,
        principal: principal, posicao: peticao.arquivos.maximum(:posicao).to_i + 1, tamanho: pdf.bytesize
      )
      arquivo.file.attach(io: StringIO.new(pdf), filename: nome, content_type: 'application/pdf')
      arquivo
    end
  end

  private

  def para_pdf(bytes, content_type)
    return bytes if content_type == 'application/pdf'
    raise ArgumentError, 'formato' unless IMAGENS.include?(content_type)

    doc = Prawn::Document.new(page_size: 'A4', margin: 24)
    doc.image StringIO.new(bytes), fit: [doc.bounds.width, doc.bounds.height]
    doc.render
  end
end
