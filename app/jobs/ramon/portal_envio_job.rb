# Documento enviado pelo painel: Drive (Clientes/<Nome — CPF>/) → tarefa ADVBOX
# "ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE" pro responsável → push ntfy.
# Cada passo é idempotente (checa a coluna antes) pra suportar retry.
class Ramon::PortalEnvioJob < ApplicationJob
  queue_as :low
  retry_on Ramon::AdvboxClient::UnavailableError, wait: :polynomially_longer, attempts: 5

  TASKS_ID_ANALISAR = '9502039'.freeze # ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE (/settings 08/09/2026)

  def perform(envio_id)
    @envio = PortalEnvio.find_by(id: envio_id)
    return unless envio_pronto?

    @cliente = @envio.portal_cliente
    @processo = @cliente.processo(@envio.lawsuit_id) || {}
    subir_drive if precisa_drive?
    abrir_tarefa if @envio.advbox_post_id.blank?
    Ramon::NtfyPushJob.perform_later(nil, title: "Documento do cliente #{@cliente.nome}",
                                          body: "#{@envio.item} · processo #{@processo['numero'].presence || @envio.lawsuit_id}")
  end

  private

  def envio_pronto? = @envio.present? && @envio.arquivo.attached?

  def precisa_drive? = @envio.drive_file_id.blank? && Ramon::DriveClient.configured?

  def subir_drive
    clientes = Ramon::DriveClient.ensure_folder('Clientes', Ramon::DriveClient.root_id)
    # ponytail: DriveExportService renomeia a pasta pra "… — COMPLETO" ao fechar o checklist;
    # ensure_folder cria uma nova se o nome mudou — aceitável (fica ao lado da antiga).
    pasta = Ramon::DriveClient.ensure_folder([@cliente.nome, @cliente.cpf.presence].compact.join(' — '), clientes)
    nome = "#{@envio.item} — #{Time.zone.today.iso8601}#{File.extname(@envio.arquivo.filename.to_s)}"
    id = @envio.arquivo.blob.open do |io|
      Ramon::DriveClient.upload(name: nome, io: io, content_type: @envio.arquivo.content_type, parent_id: pasta)
    end
    @envio.update!(drive_file_id: id)
  end

  def abrir_tarefa
    responsavel = (@processo['responsavel_id'].presence || Ramon::AdvboxClosingService::USERS_ID).to_i
    link = @envio.drive_file_id.present? ? " Drive: https://drive.google.com/file/d/#{@envio.drive_file_id}" : ''
    resp = Ramon::AdvboxClient.create_post(
      from: responsavel.to_s, guests: [responsavel], tasks_id: TASKS_ID_ANALISAR, lawsuits_id: @envio.lawsuit_id.to_s,
      start_date: Time.zone.today.iso8601,
      comments: "Cliente enviou pelo Painel do Cliente: #{@envio.item}.#{link} (envio ##{@envio.id})"
    )
    @envio.update!(advbox_post_id: resp&.dig('posts_id').to_s.presence || 'sem-id')
  rescue Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[Ramon::PortalEnvioJob] envio=#{@envio.id} advbox recusou: #{e.code}")
  end
end
