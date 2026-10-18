# Retorno público do OAuth do Google Agenda. Sem sessão: a segurança é o state (sgid com `for`, 15 min)
# + o usuário pertencer à conta. Sempre redireciona para a tela da Agenda, nunca mostra erro cru.
class Ramon::GoogleAgendaCallbacksController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    return conectar_drive if params[:state].to_s.start_with?('drive:')

    user, account_id = usuario_do_state
    return redirecionar(account_id, 'erro') unless user

    conectar(user, account_id)
    redirecionar(account_id, 'ok')
  rescue StandardError => e
    Rails.logger.error "Ramon agenda: callback falhou (#{e.class}) user=#{user&.id} account=#{account_id}"
    redirecionar(account_id, 'erro')
  end

  private

  # Conta Google do escritório pro Drive do hub (rake ramon:drive:conectar), no mesmo retorno OAuth da Agenda.
  def conectar_drive
    email = Ramon::DriveClient.conectar!(params[:state], params[:code])
    render plain: email ? "Drive do hub conectado na conta #{email}. Pode fechar esta aba." : 'Link expirado ou inválido. Gere outro.'
  rescue StandardError => e
    Rails.logger.error "Ramon drive: callback falhou (#{e.class})"
    render plain: 'Falhou ao conectar o Drive. Gere outro link.'
  end

  # state = "<sgid>:<account_id>"; rpartition porque o sgid pode ter ':' no meio.
  def usuario_do_state
    sgid, _sep, account_id = params[:state].to_s.rpartition(':')
    user = GlobalID::Locator.locate_signed(sgid, for: 'ramon_google_agenda')
    [user&.account_users&.exists?(account_id: account_id) ? user : nil, account_id]
  end

  def conectar(user, account_id)
    exigir_cifra!
    token = Ramon::GoogleAgenda::Token.oauth_client.auth_code.get_token(
      params[:code], redirect_uri: "#{ENV.fetch('FRONTEND_URL', nil)}/ramon/google_agenda/callback"
    )
    conta = GoogleAgendaConta.find_or_initialize_by(user_id: user.id)
    conta.update!(
      account_id: account_id, status: 'conectada', access_token: token.token, expira_em: Time.zone.at(token.expires_at),
      email: JWT.decode(token.params['id_token'], nil, false)[0]['email'],
      refresh_token: token.refresh_token.presence || conta.refresh_token # Google só devolve na 1ª vez; mantém o antigo
    )
  end

  def redirecionar(account_id, resultado)
    redirect_to "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account_id.to_i}/ramon/agenda?google=#{resultado}", allow_other_host: true
  end

  # Sem as chaves de cifra o token iria em claro (e ficaria assim): recusa conectar.
  def exigir_cifra!
    raise 'cifra ausente' if Rails.env.production? && !Chatwoot.encryption_configured?
  end
end
