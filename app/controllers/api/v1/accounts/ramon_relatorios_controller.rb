class Api::V1::Accounts::RamonRelatoriosController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  EMBED_HASH = '#theme=night&bordered=false&titled=false'.freeze

  def show
    site_url = ENV.fetch('RAMON_METABASE_SITE_URL', nil)
    secret = ENV.fetch('RAMON_METABASE_SECRET_KEY', nil)
    dashboard_id = ENV.fetch('RAMON_METABASE_DASHBOARD_ID', nil)
    return render json: { configured: false } if [site_url, secret, dashboard_id].any?(&:blank?)

    payload = { resource: { dashboard: dashboard_id.to_i }, params: {}, exp: 10.minutes.from_now.to_i }
    token = JWT.encode(payload, secret, 'HS256')
    render json: { configured: true, url: "#{site_url}/embed/dashboard/#{token}#{EMBED_HASH}" }
  end

  private

  def check_authorization
    authorize(:ramon_relatorio, :show?)
  end
end
