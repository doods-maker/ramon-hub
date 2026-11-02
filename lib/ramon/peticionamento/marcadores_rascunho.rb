# Sobras de rascunho (campos não preenchidos, notas internas) que não podem chegar ao tribunal.
module Ramon::Peticionamento::MarcadoresRascunho
  LISTA = [
    '[CAMPO', '[CONFERIR]', '[NB]', '[DIB]', '[CPF]', '[VALOR]', '[DATA]', '[OAB]', '[NOME DA PARTE]',
    '[ADVOGADO(A) ASSOCIADO(A)]', 'CONTROLE INTERNO', 'RASCUNHO', 'Notas ao advogado', 'Conferência humana',
    'O que esta minuta NÃO faz'
  ].freeze

  # Marcadores presentes no texto (sensível a maiúsculas; espaços/quebras valem como um espaço).
  def self.no_texto(texto)
    limpo = texto.to_s.gsub(/[[:space:]]+/, ' ')
    LISTA.select { |m| limpo.include?(m) }
  end

  # Texto de todas as páginas; '' se o PDF for criptografado, corrompido ou escaneado (sem texto).
  def self.texto_do_pdf(bytes)
    require 'pdf/reader'
    PDF::Reader.new(StringIO.new(bytes.to_s)).pages.map(&:text).join("\n")
  rescue StandardError
    ''
  end
end
