class Leads::TriageJob < ApplicationJob
  queue_as :low

  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    triage = LeadTriage.find_by(id: job.arguments.first)
    triage&.update(status: 'error', error_message: error.message.truncate(1000))
  end

  def perform(triage_id)
    triage = LeadTriage.find_by(id: triage_id)
    return if triage.blank?

    Leads::TriageService.new(triage).perform
  end
end
