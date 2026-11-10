require 'prawn'

# Põe um arquivo no pacote da petição: PDF passa; JPG/PNG viram PDF A4 de 1 página; o resto é recusado.
class Ramon::Peticionamento::AdicionarArquivo
  # O tipo declarado não basta: imagem tem de começar pela assinatura; no PDF os leitores aceitam lixo antes do %PDF- até 1024 bytes.
  PDF = '%PDF-'.b.freeze
  JPEG = "\xFF\xD8\xFF".b.freeze
  IMAGENS = { 'image/png' => "\x89PNG".b, 'image/jpeg' => JPEG, 'image/jpg' => JPEG }.freeze
  MAX_ARQUIVO = Ramon::Peticionamento::ImportarPasta::MAX_ARQUIVO
  MAX_PASTA = Ramon::Peticionamento::ImportarPasta::MAX_PASTA

  def self.call(...) = new.call(...)

  def call(peticao, bytes:, nome:, content_type:, origem:, drive_origem_id: nil, tipo: nil, principal: false) # rubocop:disable Metrics/ParameterLists
    raise ArgumentError, 'protocolada' unless peticao.editavel?

    pdf = para_pdf(bytes, content_type)
    nome = "#{File.basename(nome.to_s, '.*')}.pdf"
    # Trava: dois envios ao mesmo tempo não pegam a mesma posição nem furam o teto do pacote.
    peticao.with_lock do
      raise ArgumentError, 'pasta_grande' if peticao.arquivos.sum(:tamanho) + pdf.bytesize > MAX_PASTA

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
    raise ArgumentError, 'muito_grande' if bytes.bytesize > MAX_ARQUIVO

    inicio = bytes.byteslice(0, 1024).b
    if content_type == 'application/pdf'
      raise ArgumentError, 'formato' unless inicio.include?(PDF)

      return bytes
    end
    raise ArgumentError, 'formato' unless IMAGENS.key?(content_type) && inicio.start_with?(IMAGENS[content_type])

    imagem_para_pdf(bytes)
  end

  def imagem_para_pdf(bytes)
    doc = Prawn::Document.new(page_size: 'A4', margin: 24)
    doc.image StringIO.new(bytes), fit: [doc.bounds.width, doc.bounds.height]
    doc.render
  rescue StandardError # imagem corrompida: o Prawn falha de vários jeitos (erro próprio, Zlib, NoMethodError)
    raise ArgumentError, 'formato'
  end
end
