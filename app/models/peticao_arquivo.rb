# Um PDF do pacote de uma petição (Peticionamento · Fase 1).
class PeticaoArquivo < ApplicationRecord
  self.table_name = 'ramon_peticao_arquivos'

  belongs_to :peticao
  has_one_attached :file

  validates :tipo, inclusion: { in: Ramon::Peticionamento::Tribunais::TIPOS }
  validates :origem, inclusion: { in: %w[upload drive] }

  def nome_numerado = "#{format('%02d', posicao)} #{nome}"

  def url
    return unless file.attached?

    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    Rails.application.routes.url_helpers.rails_blob_url(file, disposition: 'attachment', filename: nome_numerado)
  end

  def as_json_hub
    {
      id: id, nome: nome, nome_numerado: nome_numerado, tipo: tipo,
      tipo_no_tribunal: Ramon::Peticionamento::Tribunais.tipo_no_tribunal(peticao.tribunal, tipo),
      posicao: posicao, principal: principal, origem: origem, tamanho: tamanho, url: url
    }
  end
end
