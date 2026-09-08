# Confere no ZapSign o status real do documento (o payload do webhook não é a
# verdade) e marca assinado no PortalAssinatura correspondente.
class Ramon::ZapsignStatusJob < ApplicationJob
  queue_as :low
  retry_on Ramon::ZapsignClient::UnavailableError, wait: :polynomially_longer, attempts: 5

  def perform(assinatura_id)
    a = PortalAssinatura.find_by(id: assinatura_id)
    return if a.nil?

    doc = Ramon::ZapsignClient.doc(a.doc_token)
    status = doc['status'].to_s
    a.update!(status: status.presence || a.status, assinado_em: (status == 'signed' ? Time.current : a.assinado_em))
  end
end
