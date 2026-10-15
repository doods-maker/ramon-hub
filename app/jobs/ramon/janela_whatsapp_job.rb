# Custo da Meta, frente D (decisão do Eduardo 15/10, comercial/docs/2026-10-15-custo-meta-estrategia.md): de hora em hora,
# avisa o SDR do lead (sem SDR: os gestores) quando faltam até 4h para fechar a janela grátis do WhatsApp. Depois dela,
# falar com o cliente só por modelo pago. A janela fecha 24h depois da última mensagem do cliente; no lead que veio de
# anúncio (meta_referral), também vale a de 72h desde a 1ª mensagem (free entry point da Meta). 1 aviso por prazo.
# ponytail: avisa das 7h às 21h, como o SLA; prazo que vence de madrugada passa sem aviso.
class Ramon::JanelaWhatsappJob < ApplicationJob
  queue_as :scheduled_jobs

  ANTES = 4.hours
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def perform
    return unless Time.current.in_time_zone(TIME_ZONE).hour.between?(7, 20)

    candidatos.find_each do |lead|
      prazo = self.class.prazo(lead.conversation, lead)
      avisar(lead, prazo) if prazo && (Time.current..Time.current + ANTES).cover?(prazo) && lead.custom_attributes['janela_avisada'] != prazo.iso8601
    end
  end

  def self.prazo(conversation, lead)
    recebidas = conversation.messages.incoming
    ultima = recebidas.maximum(:created_at)
    return if ultima.nil?

    fim = ultima + 24.hours
    lead.custom_attributes&.dig('meta_referral').present? ? [fim, recebidas.minimum(:created_at) + 72.hours].max : fim
  end

  private

  # Conversa de WhatsApp aberta, com mensagem do cliente nas últimas 72h, de lead em aberto no funil.
  def candidatos
    recentes = Message.incoming.where(created_at: 72.hours.ago..).select(:conversation_id)
    Lead.joins(:lead_stage, conversation: :inbox)
        .where(inboxes: { channel_type: 'Channel::Whatsapp' }, conversations: { status: :open, id: recentes })
        .where(lead_stages: { is_won: false, is_lost: false })
        .includes(:conversation)
  end

  def avisar(lead, prazo)
    hora = prazo.in_time_zone(TIME_ZONE).strftime('%H:%M')
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => "a janela grátis do WhatsApp fecha às #{hora}; se for retomar, mande antes" },
                                       user_ids: lead.sdr_id ? [lead.sdr_id] : Ramon::Papeis.gestor_ids(lead.account)).perform
    lead.update_columns(custom_attributes: lead.custom_attributes.merge('janela_avisada' => prazo.iso8601)) # rubocop:disable Rails/SkipsModelValidations
  end
end
