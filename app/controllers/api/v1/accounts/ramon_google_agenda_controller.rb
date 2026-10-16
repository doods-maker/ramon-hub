# Conexão do Google Agenda do usuário logado (OAuth por usuário). O retorno do Google cai em Ramon::GoogleAgendaCallbacksController.
class Api::V1::Accounts::RamonGoogleAgendaController < Api::V1::Accounts::BaseController
  SCOPE = 'openid email https://www.googleapis.com/auth/calendar.events'.freeze
  REVOKE_URL = 'https://oauth2.googleapis.com/revoke'.freeze

  def show
    conta = GoogleAgendaConta.find_by(user_id: Current.user.id)
    render json: { conectada: conta&.status == 'conectada', email: conta&.email, status: conta&.status }
  end

  def autorizacao
    sgid = Current.user.to_sgid(expires_in: 15.minutes, for: 'ramon_google_agenda').to_s
    url = Ramon::GoogleAgenda::Token.oauth_client.auth_code.authorize_url(
      redirect_uri: "#{ENV.fetch('FRONTEND_URL', nil)}/ramon/google_agenda/callback",
      scope: SCOPE, access_type: 'offline', prompt: 'consent', state: "#{sgid}:#{Current.account.id}"
    )
    render json: { url: url }
  end

  def destroy
    conta = GoogleAgendaConta.find_by(user_id: Current.user.id)
    if conta
      revogar(conta.refresh_token || conta.access_token)
      conta.destroy!
    end
    head :no_content
  end

  private

  # Best-effort: o Google pode estar fora ou o token já revogado; a conta local sai de qualquer jeito.
  def revogar(token)
    return if token.blank?

    Faraday.post(REVOKE_URL, token: token)
  rescue StandardError => e
    Rails.logger.warn "Ramon agenda: revogacao falhou (#{e.class}) user=#{Current.user.id}"
  end
end
