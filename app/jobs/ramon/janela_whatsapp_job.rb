# Custo da Meta, frente D (decisão do Eduardo 15/10, comercial/docs/2026-10-15-custo-meta-estrategia.md): de hora em hora,
# avisa o SDR do lead (sem SDR: os gestores) quando faltam até 4h para fechar a janela de texto livre do WhatsApp. Depois
# dela, falar com o cliente só por modelo. Ela fecha 24h depois da última mensagem do cliente — inclusive em lead de anúncio:
# as 72h do anúncio (free entry point da Meta) são só de PREÇO, não estendem o texto livre. 1 aviso por prazo.
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

  # Conversa de WhatsApp aberta, com mensagem do cliente nas últimas 24h, de lead em aberto no funil.
  def candidatos
    recentes = Message.incoming.where(created_at: 24.hours.ago..).select(:conversation_id)
    Lead.joins(:lead_stage, conversation: :inbox)
        .where(inboxes: { channel_type: 'Channel::Whatsapp' }, conversations: { status: :open, id: recentes })
        .where(lead_stages: { is_won: false, is_lost: false })
        .includes(:conversation)
  end

  def prazo(lead)
    ultima = lead.conversation.messages.incoming.maximum(:created_at)
    ultima && (ultima + 24.hours)
  end

  def avisar(lead, fim)
    hora = fim.in_time_zone(TIME_ZONE).strftime('%d/%m %H:%M')
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => "a janela de texto livre do WhatsApp fecha em #{hora}; depois só por modelo" },
                                       user_ids: lead.sdr_id ? [lead.sdr_id] : Ramon::Papeis.gestor_ids(lead.account)).perform
    lead.update_columns(custom_attributes: lead.custom_attributes.merge('janela_avisada' => fim.iso8601)) # rubocop:disable Rails/SkipsModelValidations
  end
end
