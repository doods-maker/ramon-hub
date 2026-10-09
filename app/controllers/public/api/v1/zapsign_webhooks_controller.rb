# Webhook do ZapSign (cadastrado por conta no painel deles, evento doc_signed;
# pro selo "Recusado" do contrato do lead, cadastrar também doc_refused).
# Casa o doc_token com a assinatura do portal OU com o contrato do lead.
# O ZapSign não assina HMAC: a auth é um header customizado com segredo fixo
# (X-Ramon-Secret) + rate-limit. O payload nunca é a verdade — o job re-consulta
# GET /docs/{token}/ antes de marcar assinado.
class Public::Api::V1::ZapsignWebhooksController < PublicController
  before_action :verify_secret

  def create
    token = params[:token].to_s
    assinatura = PortalAssinatura.find_by(doc_token: token)
    conferir(assinatura) if assinatura
    # contrato gerado pelo cartão do painel (lead.custom_attributes['zapsign'])
    lead = Lead.find_by("custom_attributes -> 'zapsign' ->> 'doc_token' = ?", token) if token.present?
    Ramon::ZapsignLeadStatusJob.perform_later(lead.id, token) if lead
    render json: { ok: true }
  end

  private

  # Regra fixa (08/10): a conferência de sempre; o gatilho "Assinatura do Painel" só avisa os fluxos comuns (N1 = B).
  def conferir(assinatura)
    Ramon::ZapsignStatusJob.perform_later(assinatura.id)
    Ramon::Fluxos::Disparo.externo('assinatura_painel', assinatura)
  end

  def verify_secret
    secret = ENV.fetch('ZAPSIGN_WEBHOOK_SECRET', nil)
    provided = request.headers['X-Ramon-Secret'].to_s
    return if secret.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
