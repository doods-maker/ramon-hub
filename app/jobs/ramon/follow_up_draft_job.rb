class Ramon::FollowUpDraftJob < ApplicationJob
  queue_as :low

  def perform(lead_id)
    lead = Lead.find_by(id: lead_id)
    return if lead.blank?
    # B4.3: com o fluxo da cadência no comando, o botão "Preparar retomada" roda o fluxo para este lead
    return Ramon::Fluxos::Retomada.disparar(lead) if Ramon::Fluxos::Retomada.assumiu?(lead.account)

    Ramon::FollowUpDraftService.new(account: lead.account).perform_for(lead)
  end
end
