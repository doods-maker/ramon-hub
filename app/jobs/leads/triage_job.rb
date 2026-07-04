class Leads::TriageJob < ApplicationJob
  queue_as :low

  def perform(triage_id)
    triage = LeadTriage.find_by(id: triage_id)
    return if triage.blank?

    Leads::TriageService.new(triage).perform
  end
end
