# Um PDF do pacote de uma petição (Peticionamento · Fase 1).
class PeticaoArquivo < ApplicationRecord
  self.table_name = 'ramon_peticao_arquivos'

  belongs_to :peticao
  has_one_attached :file
  delegate :account, to: :peticao

  # Registro de ações: quem mudou o pacote. peticao_id vai junto para nomear a petição quando o arquivo já saiu.
  audited only: %w[peticao_id nome tipo principal posicao], associated_with: :account

  validates :tipo, inclusion: { in: Ramon::Peticionamento::Tribunais::TIPOS }
  validates :origem, inclusion: { in: %w[upload drive] }

  def nome_numerado = "#{format('%02d', posicao)} #{nome}"

  # Download autenticado pela API (o front baixa via axios, com os headers do token, e salva com o nome numerado).
  def url
    return unless file.attached?

    "/api/v1/accounts/#{peticao.account_id}/ramon_peticoes/#{peticao_id}/arquivos/#{id}/baixar"
  end

  def as_json_hub
    {
      id: id, nome: nome, nome_numerado: nome_numerado, tipo: tipo,
      tipo_no_tribunal: Ramon::Peticionamento::Tribunais.tipo_no_tribunal(peticao.tribunal, tipo),
      posicao: posicao, principal: principal, origem: origem, tamanho: tamanho, url: url
    }
  end
end
