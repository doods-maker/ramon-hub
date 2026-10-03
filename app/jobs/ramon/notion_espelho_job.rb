# Espelho de status da peça no kanban "Peças" do Notion durante a transição
# (hub é a fonte da verdade). Desliga tirando RAMON_NOTION_TOKEN. Best-effort.
class Ramon::NotionEspelhoJob < ApplicationJob
  queue_as :low

  # `montando` fica de fora: gravar "aprovado" de novo acordaria o vigia local.
  MAPA = { 'rascunho' => 'rascunho', 'aprovado' => 'aprovado', 'montado' => 'montado',
           'agendado' => 'montado', 'publicado' => 'publicado' }.freeze

  def perform(peca_id)
    token = ENV.fetch('RAMON_NOTION_TOKEN', nil)
    peca = Peca.find_by(id: peca_id)
    status = MAPA[peca&.status]
    return if token.blank? || peca&.notion_page_id.blank? || status.nil?

    res = patch(peca.notion_page_id, status, token)
    Rails.logger.warn("NotionEspelho #{peca.slug}: HTTP #{res.code}") unless res.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    Rails.logger.warn("NotionEspelho falhou p/ peça #{peca_id}: #{e.class} #{e.message}")
  end

  private

  def patch(page_id, status, token)
    uri = URI("https://api.notion.com/v1/pages/#{page_id}")
    req = Net::HTTP::Patch.new(uri, 'Authorization' => "Bearer #{token}", 'Notion-Version' => '2022-06-28',
                                    'Content-Type' => 'application/json')
    req.body = { properties: { 'Status' => { select: { name: status } } } }.to_json
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
  end
end
