# Pede à Meta, uma única vez e até 24 h depois do onboarding com coexistência, os contatos do app
# (smb_app_state_sync) e depois até 6 meses de conversas (history). O conteúdo chega pelos webhooks
# `smb_app_state_sync` e `history` (Webhooks::WhatsappEventsJob) e é importado em silêncio.
class Whatsapp::Coexistencia::SincronizarJob < ApplicationJob
  queue_as :low
  # Net::OpenTimeout/ReadTimeout herdam de Timeout::Error.
  retry_on Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, wait: 1.minute, attempts: 3

  SYNC_TYPES = %w[smb_app_state_sync history].freeze

  def perform(channel_id)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless sincronizavel?(channel)

    SYNC_TYPES.each { |sync_type| pedir(channel, sync_type) }
  end

  private

  # Repetir a sincronização exige desconectar e refazer o Embedded Signup — por isso a guarda é estreita.
  # Webhook que falhou (reautorização pendente) desperdiçaria o pedido único: o conteúdo não chegaria.
  def sincronizavel?(channel)
    channel.present? &&
      channel.provider == 'whatsapp_cloud' &&
      channel.provider_config['source'] == 'embedded_signup' &&
      !channel.reauthorization_required?
  end

  def pedir(channel, sync_type)
    return if channel.provider_config.dig('coexistencia', sync_type).present?

    resposta = Whatsapp::FacebookApiClient.new(channel.provider_config['api_key'])
                                          .request_smb_app_data(channel.provider_config['phone_number_id'], sync_type)
    Whatsapp::Coexistencia.registrar!(channel, sync_type => { 'pedido_em' => Time.current.iso8601, 'request_id' => resposta&.dig('request_id') })
  rescue Timeout::Error
    raise # rede: o retry_on tenta de novo
  rescue RuntimeError => e
    # Erro HTTP da Meta (handle_response): não grava, então dá para pedir de novo.
    Rails.logger.error("[WHATSAPP] Coexistencia: pedido #{sync_type} falhou no canal #{channel.id}: #{e.message}")
  end
end
