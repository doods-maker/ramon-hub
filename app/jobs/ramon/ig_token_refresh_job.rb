# Renova o token de publicação do Instagram (vale 60 dias; renovar estende). Semanal.
class Ramon::IgTokenRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    token = GlobalConfigService.load('RAMON_IG_PUBLISH_TOKEN', nil)
    return if token.blank?

    renovar(token)
  rescue StandardError => e
    # a URL de refresh carrega o token na query: o aviso nunca leva a URL, só a mensagem (com o token mascarado)
    msg = token.present? ? e.message.to_s.gsub(token, '[token]') : e.message.to_s
    Ramon::NtfyPushJob.perform_later(nil, title: 'Token do Instagram nao renovou',
                                          body: "#{msg} — gerar outro no painel Meta e colar no super admin")
  end

  private

  def renovar(token)
    uri = URI('https://graph.instagram.com/refresh_access_token')
    uri.query = URI.encode_www_form(grant_type: 'ig_refresh_token', access_token: token)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.get(uri.request_uri) }
    novo = JSON.parse(res.body.presence || '{}')['access_token']
    raise "HTTP #{res.code}" if novo.blank?

    InstallationConfig.find_by!(name: 'RAMON_IG_PUBLISH_TOKEN').update!(value: novo)
  end
end
