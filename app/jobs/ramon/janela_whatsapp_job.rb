# Custo da Meta, frente D (decisão do Eduardo 15/10, comercial/docs/2026-10-15-custo-meta-estrategia.md): de hora em hora,
# avisa o SDR do lead (sem SDR: os gestores) quando faltam até 4h para fechar a janela grátis do WhatsApp. Depois dela,
# falar com o cliente só por modelo pago. A janela fecha 24h depois da última mensagem do cliente; a que veio de anúncio
# (referral da Meta na mensagem) vale também 72h (free entry point da Meta). 1 aviso por prazo.
# Avisa no horário do SLA (Ramon::FirstResponseSlaJob::EXPEDIENTE); na última rodada, avisa também o prazo que vence de
# madrugada.
class Ramon::JanelaWhatsappJob < ApplicationJob
  queue_as :scheduled_jobs

  ANTES = 4.hours
  TIME_ZONE = Ramon::FirstResponseSlaJob::TIME_ZONE
  EXPEDIENTE = Ramon::FirstResponseSlaJob::EXPEDIENTE

  def perform
    agora = Time.current.in_time_zone(TIME_ZONE)
    return unless EXPEDIENTE.cover?(agora.hour)

    ate = agora.hour == EXPEDIENTE.end ? agora.tomorrow.change(hour: EXPEDIENTE.begin) : agora + ANTES
    candidatos.find_each do |lead|
      fim = prazo(lead)
      avisar(lead, fim) if fim && (agora..ate).cover?(fim) && lead.custom_attributes['janela_avisada'] != fim.iso8601
    end
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

  def prazo(lead)
    recebidas = lead.conversation.messages.incoming
    ultima = recebidas.maximum(:created_at)
    return if ultima.nil?

    # content_attributes é um store (texto JSON na coluna): o referral se lê no Ruby. Só as últimas 72h podem abrir janela.
    anuncio = recebidas.where(created_at: 72.hours.ago..).select { |m| m.content_attributes['referral'].present? }.map(&:created_at).max
    [ultima + 24.hours, anuncio && (anuncio + 72.hours)].compact.max
  end

  def avisar(lead, fim)
    hora = fim.in_time_zone(TIME_ZONE).strftime('%d/%m %H:%M')
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => "a janela grátis do WhatsApp fecha em #{hora}; se for retomar, mande antes" },
                                       user_ids: lead.sdr_id ? [lead.sdr_id] : Ramon::Papeis.gestor_ids(lead.account)).perform
    lead.update_columns(custom_attributes: lead.custom_attributes.merge('janela_avisada' => fim.iso8601)) # rubocop:disable Rails/SkipsModelValidations
  end
end
