# Renova os tokens do Instagram (valem 60 dias; renovar estende). Semanal.
# Publicação: token do super admin. Caixas: o token só renovava quando a caixa era usada.
class Ramon::IgTokenRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    renovar_publicacao
    Channel::Instagram.find_each { |canal| conferir_caixa(canal) }
  end

  private

  def renovar_publicacao
    token = GlobalConfigService.load('RAMON_IG_PUBLISH_TOKEN', nil)
    return if token.blank?

    renovar(token)
  rescue StandardError => e
    # a URL de refresh carrega o token na query: o aviso nunca leva a URL, só a mensagem (com o token mascarado)
    msg = token.present? ? e.message.to_s.gsub(token, '[token]') : e.message.to_s
    Ramon::NtfyPushJob.perform_later(nil, title: 'Token do Instagram nao renovou',
                                          body: "#{msg} — gerar outro no painel Meta e colar no super admin")
  end

  # Instagram::RefreshOauthTokenService renova a menos de 10 dias do vencimento e engole o erro.
  # Semanal cai 1 ou 2 vezes nessa janela; se ainda faltar menos de 10 dias depois, não renovou.
  # ponytail: sem nova tentativa; o aviso chega com uns 4 dias de folga para reconectar.
  def conferir_caixa(canal)
    canal.access_token # o getter é que renova
    return if canal.reload.expires_at > 10.days.from_now

    avisar_caixa(canal)
  rescue StandardError
    avisar_caixa(canal)
  end

  def avisar_caixa(canal)
    Ramon::NtfyPushJob.perform_later(nil, title: 'Token da caixa do Instagram nao renovou',
                                          body: "#{canal.inbox&.name} — reconectar a caixa no hub")
  end

  def renovar(token)
    uri = URI('https://graph.instagram.com/refresh_access_token')
    uri.query = URI.encode_www_form(grant_type: 'ig_refresh_token', access_token: token)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.get(uri.request_uri) }
    novo = JSON.parse(res.body.presence || '{}')['access_token']
    raise "HTTP #{res.code}" if novo.blank?

    InstallationConfig.find_by!(name: 'RAMON_IG_PUBLISH_TOKEN').update!(value: novo)
  end
end
