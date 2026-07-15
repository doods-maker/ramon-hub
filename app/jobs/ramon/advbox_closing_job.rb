# Disparado quando um lead é marcado como ganho (Lead#enqueue_advbox_closing).
class Ramon::AdvboxClosingJob < ApplicationJob
  queue_as :low
  retry_on Ramon::AdvboxClient::UnavailableError, wait: :polynomially_longer, attempts: 3

  def perform(lead_id)
    lead = Lead.find_by(id: lead_id)
    return if lead.blank?

    Ramon::AdvboxClosingService.new(lead).perform
  end
end
