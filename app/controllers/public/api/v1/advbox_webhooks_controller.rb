# Receiver dos HTTP Requests do Flowter (ADVBOX). O Flowter só suporta um
# header de Authorization estático (não assina HMAC como o Cal.com), então a
# auth é Bearer fixo + rate-limit no rack_attack. Responde rápido e processa
# assíncrono (o Flowter não deve esperar).
class Public::Api::V1::AdvboxWebhooksController < PublicController
  before_action :verify_token

  def create
    event = AdvboxEvent.find_or_initialize_by(account: account, event_key: event_key)
    if event.new_record?
      event.update!(payload: parsed_payload)
      Ramon::AdvboxEventJob.perform_later(event.id)
    end
    render json: { ok: true }
  rescue ActiveRecord::RecordNotUnique
    render json: { ok: true } # corrida entre reentregas do Flowter — já capturado
  end

  private

  def verify_token
    secret = ENV.fetch('ADVBOX_WEBHOOK_TOKEN', nil)
    return head :unauthorized if secret.blank? || account.blank?

    provided = request.headers['Authorization'].to_s.delete_prefix('Bearer ').strip
    return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end

  # Mesma conta única dos endpoints de leads/Cal.com.
  def account
    @account ||= Account.find_by(id: ENV.fetch('RAMON_LEAD_CAPTURE_ACCOUNT_ID', nil))
  end

  # Idempotência: reentrega com corpo idêntico = mesmo evento.
  def event_key
    @event_key ||= Digest::SHA256.hexdigest(request.raw_post.presence || request.request_parameters.to_json)
  end

  # Modo captura: aceita JSON ou form-encoded e guarda o que vier — o parser
  # do processor é defensivo porque o schema real só se confirma no disparo.
  def parsed_payload
    data = JSON.parse(request.raw_post)
    data.is_a?(Hash) ? data : { '_data' => data }
  rescue JSON::ParserError
    request.request_parameters.presence || { '_raw' => request.raw_post }
  end
end
