require 'google/apis/drive_v3'
require 'googleauth'

# Ponte hub → Google Drive (ADR-0002). Service account: o Eduardo compartilha a
# pasta-raiz com o e-mail da conta de serviço; sem as envs, feature desligada.
class Ramon::DriveClient
  FOLDER_MIME = 'application/vnd.google-apps.folder'.freeze
  SHORTCUT_MIME = 'application/vnd.google-apps.shortcut'.freeze
  FILTRO_TIPOS = "(mimeType = '#{FOLDER_MIME}' or mimeType = 'application/pdf' or mimeType = 'image/jpeg' or mimeType = 'image/png')".freeze
  MARCADOR_PASTA_PRONTA = '_pasta-pronta.json'.freeze
  MARCADOR_PASTA_USADA = '_pasta-pronta.usada.json'.freeze
  SCOPE = 'https://www.googleapis.com/auth/drive'.freeze

  class << self
    def configured?
      (ENV.fetch('RAMON_DRIVE_CREDENTIALS', nil).present? || refresh_token.present?) && ENV.fetch('RAMON_DRIVE_ROOT_ID', nil).present?
    end

    # Conexão da conta Google do escritório (rake ramon:drive:conectar). Reaproveita o cliente OAuth e o
    # retorno já cadastrados da Agenda; o state "drive:" separa os dois no callback.
    def url_conexao
      state = "drive:#{Rails.application.message_verifier(:ramon_google_drive).generate('drive', expires_in: 15.minutes)}"
      Ramon::GoogleAgenda::Token.oauth_client.auth_code.authorize_url(
        redirect_uri: redirect_uri, scope: "openid email #{SCOPE}", access_type: 'offline', prompt: 'consent', state: state
      )
    end

    # Devolve o e-mail conectado; nil se o state não vale ou o Google não mandou refresh token.
    def conectar!(state, code)
      return unless Rails.application.message_verifier(:ramon_google_drive).verified(state.to_s.delete_prefix('drive:')) == 'drive'

      token = Ramon::GoogleAgenda::Token.oauth_client.auth_code.get_token(code, redirect_uri: redirect_uri)
      return if token.refresh_token.blank?

      InstallationConfig.where(name: 'RAMON_DRIVE_REFRESH_TOKEN').first_or_initialize.update!(value: token.refresh_token, locked: false)
      GlobalConfig.clear_cache
      JWT.decode(token.params['id_token'], nil, false)[0]['email']
    end

    def root_id = ENV.fetch('RAMON_DRIVE_ROOT_ID')

    # Id que entra numa query do Drive: só caracteres de id (o que vem da tela não pode fechar a aspa e mudar o filtro).
    def id_de_query!(id) = id.to_s.match?(/\A[\w-]+\z/) ? id : raise(ArgumentError, 'id_do_drive_invalido')

    # Acha (ou cria) subpasta pelo nome exato dentro do pai. Nome vai escapado na query.
    def ensure_folder(name, parent_id)
      q = "name = '#{name.gsub("'", "\\\\'")}' and '#{id_de_query!(parent_id)}' in parents " \
          "and mimeType = '#{FOLDER_MIME}' and trashed = false"
      existing = service.list_files(q: q, fields: 'files(id)').files.first
      return existing.id if existing

      service.create_file({ name: name, mime_type: FOLDER_MIME, parents: [parent_id] }, fields: 'id').id
    end

    def upload(name:, io:, content_type:, parent_id:)
      service.create_file({ name: name, parents: [parent_id] },
                          upload_source: io, content_type: content_type, fields: 'id').id
    end

    # Mesmo nome (arquivo, não pasta) na pasta: troca o conteúdo e mantém o id; senão sobe novo.
    def substituir(name:, io:, content_type:, parent_id:)
      existente = conteudo_da_pasta(parent_id).find { |f| !f[:pasta] && f[:name] == name }
      return upload(name: name, io: io, content_type: content_type, parent_id: parent_id) unless existente

      service.update_file(existente[:id], upload_source: io, content_type: content_type, supports_all_drives: true)
      existente[:id]
    end

    def shortcut(target_id:, name:, parent_id:)
      service.create_file({ name: name, mime_type: SHORTCUT_MIME, parents: [parent_id],
                            shortcut_details: { target_id: target_id } }, fields: 'id').id
    end

    def rename(file_id, name)
      service.update_file(file_id, { name: name }, fields: 'id', supports_all_drives: true)
    end

    # Navegador de arquivos do Drive (Peticionamento): só pastas, PDF e JPG/PNG; pastas primeiro.
    def children(parent_id)
      listar("'#{id_de_query!(parent_id)}' in parents and #{FILTRO_TIPOS}", 200)
    end

    # Tudo que está na pasta (sem filtro de tipos), pastas incluídas com pasta: true.
    def conteudo_da_pasta(pasta_id)
      ordenados(todas_as_paginas("'#{id_de_query!(pasta_id)}' in parents and trashed = false", 'files(id,name,mimeType,modifiedTime,size,parents)'))
    end

    # Marcadores que a esteira deixa na pasta pronta: [{id:, parents:, size:}]; a pasta é o pai do marcador.
    # Segue as páginas até o fim (qualquer erro sobe: lista parcial nunca vale como completa).
    def marcadores_de_pasta_pronta
      todas_as_paginas("name = '#{MARCADOR_PASTA_PRONTA}' and trashed = false", 'files(id,parents,size)')
        .map { |f| { id: f.id, parents: f.parents, size: f.size&.to_i } }
    end

    # Marcador já usado: renomeado sai da busca. Lixeira não serve: no Drive só o dono manda à lixeira, e renomear basta ser editor.
    def aposentar_marcador(file_id)
      rename(file_id, MARCADOR_PASTA_USADA)
    end

    # A pasta está dentro da raiz do escritório (sobe até `niveis` pais)?
    def dentro_da_raiz?(pasta_id, niveis: 8)
      atual = pasta_id
      niveis.times do
        return true if atual == root_id

        atual = parent_of(atual)
        return false if atual.blank?
      end
      atual == root_id
    end

    # Nomes das pastas ancestrais (mais próxima primeiro), até `limite`.
    def nomes_acima(pasta_id, limite: 4)
      nomes = []
      atual = pasta_id
      limite.times do
        atual = parent_of(atual)
        break if atual.blank?

        nomes << service.get_file(atual, fields: 'name', supports_all_drives: true).name
      end
      nomes
    end

    def search(texto)
      texto = texto.to_s.strip
      return [] if texto.length < 3

      listar("name contains '#{texto.gsub(/[\\']/) { |c| "\\#{c}" }}' and #{FILTRO_TIPOS}", 50)
    end

    # Só pasta existente: erro de cliente do Drive (404 de id inexistente) é false; erro de servidor sobe.
    def pasta?(id)
      service.get_file(id, fields: 'mimeType', supports_all_drives: true).mime_type == FOLDER_MIME
    rescue Google::Apis::ClientError
      false
    end

    def parent_of(id)
      service.get_file(id, fields: 'parents', supports_all_drives: true).parents&.first
    end

    # => [bytes, mime_type, name]
    def download(file_id)
      meta = service.get_file(file_id, fields: 'name,mimeType', supports_all_drives: true)
      io = StringIO.new
      service.get_file(file_id, download_dest: io, supports_all_drives: true)
      [io.string, meta.mime_type, meta.name]
    end

    private

    def listar(filtro, page_size)
      files = service.list_files(
        q: "#{filtro} and trashed = false", fields: 'files(id,name,mimeType,modifiedTime,size,parents)', page_size: page_size,
        supports_all_drives: true, include_items_from_all_drives: true
      ).files.to_a
      ordenados(files)
    end

    def ordenados(files) = files.map { |f| arquivo_hash(f) }.sort_by { |h| [h[:pasta] ? 0 : 1, h[:name].to_s.downcase] }

    def todas_as_paginas(filtro, campos)
      arquivos = []
      token = nil
      loop do
        pagina = service.list_files(q: filtro, fields: "nextPageToken,#{campos}", page_size: 200, page_token: token,
                                    supports_all_drives: true, include_items_from_all_drives: true)
        arquivos.concat(pagina.files.to_a)
        token = pagina.next_page_token
        break if token.blank?
      end
      arquivos
    end

    def arquivo_hash(file)
      { id: file.id, name: file.name, mime_type: file.mime_type, modified_time: file.modified_time,
        size: file.size&.to_i, parents: file.parents, pasta: file.mime_type == FOLDER_MIME }
    end

    def redirect_uri = "#{ENV.fetch('FRONTEND_URL', nil)}/ramon/google_agenda/callback"

    def refresh_token = GlobalConfigService.load('RAMON_DRIVE_REFRESH_TOKEN', nil)

    # Service account não tem cota no "Meu Drive" (storageQuotaExceeded em todo arquivo com conteúdo):
    # com a conta do escritório conectada, grava como ela. Recria o cliente se o token mudar.
    def service
      token = refresh_token
      return @service if @service && @token == token

      @token = token
      @service = Google::Apis::DriveV3::DriveService.new.tap do |s|
        s.authorization = token.present? ? conta_do_escritorio(token) : service_account
      end
    end

    def conta_do_escritorio(token)
      Google::Auth::UserRefreshCredentials.new(
        client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil),
        client_secret: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil),
        refresh_token: token, scope: SCOPE
      )
    end

    def service_account
      Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: File.open(ENV.fetch('RAMON_DRIVE_CREDENTIALS')), scope: SCOPE)
    end
  end
end
