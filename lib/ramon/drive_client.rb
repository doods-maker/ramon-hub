require 'google/apis/drive_v3'
require 'googleauth'

# Ponte hub → Google Drive (ADR-0002). Service account: o Eduardo compartilha a
# pasta-raiz com o e-mail da conta de serviço; sem as envs, feature desligada.
class Ramon::DriveClient
  FOLDER_MIME = 'application/vnd.google-apps.folder'.freeze
  SHORTCUT_MIME = 'application/vnd.google-apps.shortcut'.freeze

  class << self
    def configured?
      ENV.fetch('RAMON_DRIVE_CREDENTIALS', nil).present? && ENV.fetch('RAMON_DRIVE_ROOT_ID', nil).present?
    end

    def root_id = ENV.fetch('RAMON_DRIVE_ROOT_ID')

    # Acha (ou cria) subpasta pelo nome exato dentro do pai. Nome vai escapado na query.
    def ensure_folder(name, parent_id)
      q = "name = '#{name.gsub("'", "\\\\'")}' and '#{parent_id}' in parents " \
          "and mimeType = '#{FOLDER_MIME}' and trashed = false"
      existing = service.list_files(q: q, fields: 'files(id)').files.first
      return existing.id if existing

      service.create_file({ name: name, mime_type: FOLDER_MIME, parents: [parent_id] }, fields: 'id').id
    end

    def upload(name:, io:, content_type:, parent_id:)
      service.create_file({ name: name, parents: [parent_id] },
                          upload_source: io, content_type: content_type, fields: 'id').id
    end

    def shortcut(target_id:, name:, parent_id:)
      service.create_file({ name: name, mime_type: SHORTCUT_MIME, parents: [parent_id],
                            shortcut_details: { target_id: target_id } }, fields: 'id').id
    end

    def rename(file_id, name)
      service.update_file(file_id, { name: name }, fields: 'id')
    end

    private

    def service
      @service ||= Google::Apis::DriveV3::DriveService.new.tap do |s|
        s.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: File.open(ENV.fetch('RAMON_DRIVE_CREDENTIALS')),
          scope: 'https://www.googleapis.com/auth/drive'
        )
      end
    end
  end
end
