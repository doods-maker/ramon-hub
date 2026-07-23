# SLA de 1ª resposta (mapa comercial 23/07): agendado pelo RamonLeadListener
# quando a conversa nasce em inbox de lead. No fire, só apita se a conversa
# seguir aberta e sem primeira resposta.
class Ramon::FirstResponseSlaJob < ApplicationJob
  queue_as :low

  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || conversation.first_reply_created_at.present? || !conversation.open?
    return unless business_hours?

    lead = conversation.account.leads.find_by(conversation_id: conversation.id)
    return if lead.blank?

    minutes = ENV.fetch('RAMON_SLA_FIRST_RESPONSE_MINUTES', '15')
    Ramon::NtfyPushJob.perform_now(lead.id, title: 'Lead aguardando 1a resposta',
                                            body: "Lead aguardando 1ª resposta há #{minutes}min: #{lead.name}")
  end

  private

  # Só push entre 07–21 do escritório: fora disso ninguém responde mesmo —
  # a manhã seguinte é coberta pelo /bom-dia.
  def business_hours?
    Time.current.in_time_zone(TIME_ZONE).hour.between?(7, 20)
  end
end
