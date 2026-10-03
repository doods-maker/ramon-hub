# Acervo: depois de publicada, a peça (JPEGs + legenda) vai pra
# Posts Instagram/<Carrossel|Estático>/<rodada — gancho> no Drive. Best-effort.
class Ramon::ConteudoDriveJob < ApplicationJob
  queue_as :low

  def perform(peca_id)
    raiz = ENV.fetch('RAMON_DRIVE_POSTS_ID', nil)
    return if raiz.blank? || !Ramon::DriveClient.configured?

    peca = Peca.find(peca_id)
    tipo = Ramon::DriveClient.ensure_folder(peca.tipo == 'carrossel' ? 'Carrossel' : 'Estático', raiz)
    pasta = Ramon::DriveClient.ensure_folder("#{peca.rodada.iso8601} — #{peca.gancho.delete('/\:*?"<>|')}", tipo)
    peca.imagens.each do |url|
      nome = File.basename(URI(url).path)
      Ramon::DriveClient.upload(name: nome, io: StringIO.new(Net::HTTP.get(URI(url))), content_type: 'image/jpeg', parent_id: pasta)
    end
    Ramon::DriveClient.upload(name: 'legenda.txt', io: StringIO.new(peca.legenda.to_s), content_type: 'text/plain', parent_id: pasta)
    peca.update!(drive_pasta_id: pasta)
  end
end
