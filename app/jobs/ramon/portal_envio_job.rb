# Documento enviado pelo painel: Drive (Clientes/<Nome — CPF>/) → push ntfy →
# tarefa ADVBOX "ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE" pro responsável +
# tarefa "ORGANIZAR DOCUMENTOS" pra secretária anexar o arquivo no ADVBOX (a API
# do ADVBOX não recebe arquivo — ADR 0002; decisão Eduardo 28/09: 2 tarefas juntas).
# Ntfy vem antes da tarefa: se o ADVBOX cair (retry_on → discard depois de 5
# tentativas), o humano já foi avisado do documento mesmo assim.
# Cada passo é idempotente (checa a coluna antes) pra suportar retry.
class Ramon::PortalEnvioJob < ApplicationJob
  queue_as :low
  retry_on Ramon::AdvboxClient::UnavailableError, wait: :polynomially_longer, attempts: 5

  TASKS_ID_ANALISAR = '9502039'.freeze # ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE (/settings 08/09/2026)
  TASKS_ID_JUNTADA = '8745531'.freeze # ORGANIZAR DOCUMENTOS (/settings 28/09/2026)
  SECRETARIA_ID = 260_014 # Gabriela (recepção) no ADVBOX

  def perform(envio_id)
    @envio = PortalEnvio.find_by(id: envio_id)
    return unless envio_pronto?

    @cliente = @envio.portal_cliente
    @processo = @cliente.processo(@envio.lawsuit_id) || {}
    subir_drive if precisa_drive?
    Ramon::NtfyPushJob.perform_later(nil, title: "Documento do cliente #{@cliente.nome}",
                                          body: "#{@envio.item} · processo #{@processo['numero'].presence || @envio.lawsuit_id}")
    abrir_tarefa if @envio.advbox_post_id.blank?
    abrir_juntada if @envio.juntada_post_id.blank?
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
    post_id = criar_tarefa(responsavel, TASKS_ID_ANALISAR, "Cliente enviou pelo Painel do Cliente: #{@envio.item}.#{link_drive}")
    @envio.update!(advbox_post_id: post_id) if post_id
  end

  def abrir_juntada
    texto = "Anexar no ADVBOX o documento que o cliente enviou pelo Painel do Cliente: #{@envio.item}.#{link_drive}"
    post_id = criar_tarefa(SECRETARIA_ID, TASKS_ID_JUNTADA, texto)
    @envio.update!(juntada_post_id: post_id) if post_id
  end

  def link_drive = @envio.drive_file_id.present? ? " Drive: https://drive.google.com/file/d/#{@envio.drive_file_id}" : ''

  # Devolve o id da tarefa ('sem-id' se o ADVBOX não devolver) ou nil se recusou.
  def criar_tarefa(usuario, tasks_id, comentario)
    resp = Ramon::AdvboxClient.create_post(
      from: usuario.to_s, guests: [usuario], tasks_id: tasks_id, lawsuits_id: @envio.lawsuit_id.to_s,
      start_date: Time.zone.today.iso8601, comments: "#{comentario} (envio ##{@envio.id})"
    )
    resp&.dig('posts_id').to_s.presence || 'sem-id'
  rescue Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[Ramon::PortalEnvioJob] envio=#{@envio.id} tarefa #{tasks_id} recusada: #{e.code}")
    nil
  end
end
