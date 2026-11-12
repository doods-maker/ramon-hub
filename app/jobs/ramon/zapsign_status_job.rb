# Confere no ZapSign o status real do documento (o payload do webhook não é a
# verdade) e marca assinado no PortalAssinatura correspondente.
# O gatilho "Assinatura do Painel" dispara aqui, depois da conferência, só quando a assinatura é confirmada (decisão de 12/11/2026).
# ZapSign fora do ar depois das 5 tentativas: não dispara (nada confirmado).
class Ramon::ZapsignStatusJob < ApplicationJob
  queue_as :low
  retry_on Ramon::ZapsignClient::UnavailableError, wait: :polynomially_longer, attempts: 5

  def perform(assinatura_id)
    a = PortalAssinatura.find_by(id: assinatura_id)
    return if a.nil? || a.status == 'cancelado' # cancelado no hub: o "refused" do ZapSign não sobrescreve

    status = conferido(a)
    a.update!(status: status || a.status, assinado_em: (status == 'signed' ? Time.current : a.assinado_em))
    Ramon::Fluxos::Disparo.externo('assinatura_painel', a) if a.saved_change_to_status? && a.status == 'signed' # Disparo não levanta erro
  end

  private

  # Status do ZapSign; nil mantém o do hub (o 'pending' deles é o 'pendente' do hub, do scope pendentes).
  def conferido(assinatura)
    status = Ramon::ZapsignClient.doc(assinatura.doc_token)['status'].to_s
    status.presence unless status == 'pending'
  end
end
