# Access token válido da conta Google do usuário: renova quando faltam menos de 5 min.
# Refresh revogado (invalid_grant) → conta 'desconectada' e nil; rede fora → Transitorio (quem chama tenta depois).
module Ramon::GoogleAgenda::Token
  class Transitorio < StandardError; end

  MARGEM = 5.minutes

  module_function

  # Mesmo cliente do GoogleConcern#google_client.
  def oauth_client
    ::OAuth2::Client.new(
      GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil),
      GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil),
      site: 'https://oauth2.googleapis.com',
      authorize_url: 'https://accounts.google.com/o/oauth2/auth',
      token_url: 'https://accounts.google.com/o/oauth2/token'
    )
  end

  def valido(conta)
    return nil if conta.nil? || conta.status != 'conectada'
    return conta.access_token if conta.expira_em && conta.expira_em > MARGEM.from_now

    renovar(conta)
  end

  def renovar(conta)
    atual = ::OAuth2::AccessToken.new(
      oauth_client, conta.access_token, refresh_token: conta.refresh_token, expires_at: conta.expira_em.to_i
    )
    novo = atual.refresh!
    conta.update!(access_token: novo.token, refresh_token: novo.refresh_token.presence || conta.refresh_token,
                  expira_em: Time.zone.at(novo.expires_at))
    conta.access_token
  rescue ::OAuth2::Error => e
    raise unless e.code == 'invalid_grant'

    conta.update!(status: 'desconectada')
    nil
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError
    raise Transitorio
  end
end
