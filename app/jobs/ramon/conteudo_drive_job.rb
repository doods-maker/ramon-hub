# Acervo: depois de publicada, a peça (JPEGs + legenda) vai pra
# Posts Instagram/<Carrossel|Estático>/<rodada — gancho> no Drive. Best-effort.
class Ramon::ConteudoDriveJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: 1.minute, attempts: 3

  def perform(peca_id)
    raiz = ENV.fetch('RAMON_DRIVE_POSTS_ID', nil)
    return if raiz.blank? || !Ramon::DriveClient.configured?

    peca = Peca.find(peca_id)
    tipo = Ramon::DriveClient.ensure_folder(peca.tipo == 'carrossel' ? 'Carrossel' : 'Estático', raiz)
    pasta = Ramon::DriveClient.ensure_folder("#{peca.rodada.iso8601} — #{peca.gancho.delete('/\:*?"<>|')}", tipo)
    subir_imagens(peca, pasta)
    Ramon::DriveClient.upload(name: 'legenda.txt', io: StringIO.new(peca.legenda.to_s), content_type: 'text/plain', parent_id: pasta)
    peca.update!(drive_pasta_id: pasta)
  end

  private

  def subir_imagens(peca, pasta)
    peca.imagens.each do |url|
      resposta = Net::HTTP.get_response(URI(url))
      raise "Download falhou (#{resposta.code}): #{url}" unless resposta.is_a?(Net::HTTPSuccess)

      Ramon::DriveClient.upload(name: File.basename(URI(url).path), io: StringIO.new(resposta.body), content_type: 'image/jpeg', parent_id: pasta)
    end
  end
end
