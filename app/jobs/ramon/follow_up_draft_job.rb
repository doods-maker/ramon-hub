class Ramon::FollowUpDraftJob < ApplicationJob
  queue_as :low

  def perform(lead_id)
    lead = Lead.find_by(id: lead_id)
    return if lead.blank?

    Ramon::FollowUpDraftService.new(account: lead.account).perform_for(lead)
  end
end
