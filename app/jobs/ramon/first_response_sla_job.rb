# SLA de 1ª resposta (mapa comercial 23/07; playbook operacional §2): agendado
# pelo RamonLeadListener quando a conversa nasce em inbox de lead. No fire, só
# apita se a conversa seguir aberta e sem primeira resposta.
# 1º disparo (N min): sino do SDR do lead (sem SDR → gestores) + ntfy.
# Escalada (60 min da criação, "nunca > 1h"): sino dos gestores.
class Ramon::FirstResponseSlaJob < ApplicationJob
  queue_as :low

  TIME_ZONE = 'America/Sao_Paulo'.freeze
  ESCALADA = 60.minutes

  def perform(conversation_id, escalada = false) # rubocop:disable Style/OptionalBooleanParameter
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || conversation.first_reply_created_at.present? || !conversation.open?

    lead = conversation.account.leads.find_by(conversation_id: conversation.id)
    return if lead.blank?

    schedule_escalation(conversation) unless escalada
    return unless business_hours?

    escalada ? escalate(lead) : alert(lead, Ramon::Cadencia.sla_minutes(conversation.inbox))
  end

  private

  def alert(lead, minutes)
    destinatarios = lead.sdr_id ? [lead.sdr_id] : Ramon::Papeis.gestor_ids(lead.account)
    notify(lead, destinatarios, minutes)
    Ramon::NtfyPushJob.perform_now(lead.id, title: 'Lead aguardando 1a resposta',
                                            body: "Lead aguardando 1ª resposta há #{minutes}min: #{lead.name}")
  end

  def escalate(lead)
    notify(lead, Ramon::Papeis.gestor_ids(lead.account), ESCALADA.in_minutes.to_i)
  end

  def notify(lead, user_ids, minutes)
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_sla_breach',
                                       meta: { 'minutos' => minutes.to_s }, user_ids: user_ids).perform
  end

  def schedule_escalation(conversation)
    at = conversation.created_at + ESCALADA
    self.class.set(wait_until: at).perform_later(conversation.id, true) if at.future?
  end

  # Só alerta entre 07–21 do escritório: fora disso ninguém responde mesmo —
  # a manhã seguinte é coberta pelo /bom-dia.
  def business_hours?
    Time.current.in_time_zone(TIME_ZONE).hour.between?(7, 20)
  end
end
