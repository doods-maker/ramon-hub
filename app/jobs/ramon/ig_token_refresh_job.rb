# Renova os tokens do Instagram (valem 60 dias; renovar estende). Semanal.
# Publicação: token do super admin. Caixas: o token só renovava quando a caixa era usada.
class Ramon::IgTokenRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channel::Instagram.find_each { |canal| renovar_caixa(canal) }

    token = GlobalConfigService.load('RAMON_IG_PUBLISH_TOKEN', nil)
    renovar(token) if token.present?
  rescue StandardError => e
    # a URL de refresh carrega o token na query: o aviso nunca leva a URL, só a mensagem (com o token mascarado)
    msg = token.present? ? e.message.to_s.gsub(token, '[token]') : e.message.to_s
    Ramon::NtfyPushJob.perform_later(nil, title: 'Token do Instagram nao renovou',
                                          body: "#{msg} — gerar outro no painel Meta e colar no super admin")
  end

  private

  # O serviço do canal renova a 10 dias do vencimento e engole o erro; rodar toda semana cai nessa janela.
  # Se depois disso ainda faltar menos de 10 dias, não renovou.
  def renovar_caixa(canal)
    canal.access_token
    return if canal.reload.expires_at.present? && canal.expires_at > 10.days.from_now

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
