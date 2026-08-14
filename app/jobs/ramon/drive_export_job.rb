require 'google/apis/drive_v3' # garante Google::Apis::TransmissionError/ServerError carregados no class body

class Ramon::DriveExportJob < ApplicationJob
  queue_as :low
  retry_on Google::Apis::TransmissionError, Google::Apis::ServerError, wait: :polynomially_longer, attempts: 3

  def perform(lead_id)
    lead = Lead.find_by(id: lead_id)
    return if lead.blank?

    Ramon::DriveExportService.new(lead).perform
  end
end
