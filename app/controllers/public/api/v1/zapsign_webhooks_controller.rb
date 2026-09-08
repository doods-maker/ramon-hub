# Webhook do ZapSign (cadastrado por conta no painel deles, evento doc_signed).
# O ZapSign não assina HMAC: a auth é um header customizado com segredo fixo
# (X-Ramon-Secret) + rate-limit. O payload nunca é a verdade — o job re-consulta
# GET /docs/{token}/ antes de marcar assinado.
class Public::Api::V1::ZapsignWebhooksController < PublicController
  before_action :verify_secret

  def create
    assinatura = PortalAssinatura.find_by(doc_token: params[:token].to_s)
    Ramon::ZapsignStatusJob.perform_later(assinatura.id) if assinatura
    render json: { ok: true }
  end

  private

  def verify_secret
    secret = ENV.fetch('ZAPSIGN_WEBHOOK_SECRET', nil)
    provided = request.headers['X-Ramon-Secret'].to_s
    return if secret.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
