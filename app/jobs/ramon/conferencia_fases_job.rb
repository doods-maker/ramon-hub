# Noturno: refaz a Conferência de fases de cada conta (Ramon::ConferenciaFases#atualizar!). Se o ADVBOX cair no
# meio, o que já foi salvo fica e a próxima noite continua de onde parou.
class Ramon::ConferenciaFasesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      Ramon::ConferenciaFases.new(account).atualizar!
    rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
      Rails.logger.warn("[Ramon::ConferenciaFasesJob] account=#{account.id} #{e.class}: #{e.message}")
    end
  end
end
