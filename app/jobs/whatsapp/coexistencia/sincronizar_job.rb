# Pede à Meta, uma única vez e até 24 h depois do onboarding com coexistência, os contatos do app
# (smb_app_state_sync) e depois até 6 meses de conversas (history). O conteúdo chega pelos webhooks
# `smb_app_state_sync` e `history` (Webhooks::WhatsappEventsJob) e é importado em silêncio.
class Whatsapp::Coexistencia::SincronizarJob < ApplicationJob
  queue_as :low
  # Net::OpenTimeout/ReadTimeout herdam de Timeout::Error.
  retry_on Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, wait: 1.minute, attempts: 3
  # 429/5xx da Meta: 6 tentativas em ~20 min, bem dentro das 24 h da janela. Esgotou, avisa.
  retry_on Whatsapp::Coexistencia::ErroTransitorio, wait: :polynomially_longer, attempts: 6 do
    avisar('Sincronizacao do WhatsApp falhou', "A Meta seguiu indisponível. #{REFAZER}")
  end

  SYNC_TYPES = %w[smb_app_state_sync history].freeze
  REFAZER = 'Contatos e histórico do app não vieram; repetir exige desconectar e refazer o Embedded Signup pela caixa.'.freeze

  def self.avisar(titulo, corpo)
    Ramon::NtfyPushJob.perform_later(title: titulo, body: corpo)
  end

  def perform(channel_id)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless sincronizavel?(channel)
    # Webhook que falhou (reautorização pendente) desperdiçaria o pedido único: o conteúdo não chegaria.
    return self.class.avisar('Sincronizacao do WhatsApp nao pedida', "O canal pede reautorização. #{REFAZER}") if channel.reauthorization_required?

    SYNC_TYPES.each { |sync_type| pedir(channel, sync_type) }
  rescue Timeout::Error
    raise # rede: o retry_on tenta de novo
  rescue RuntimeError => e
    # Erro HTTP definitivo da Meta (handle_response): não grava nem segue para o próximo pedido.
    Rails.logger.error("[WHATSAPP] Coexistencia: pedido de sincronizacao falhou no canal #{channel_id}: #{e.message}")
    self.class.avisar('Sincronizacao do WhatsApp falhou', "A Meta recusou o pedido. #{REFAZER}")
  end

  private

  # Repetir a sincronização exige desconectar e refazer o Embedded Signup — por isso a guarda é estreita.
  def sincronizavel?(channel)
    channel.present? &&
      channel.provider == 'whatsapp_cloud' &&
      channel.provider_config['source'] == 'embedded_signup'
  end

  def pedir(channel, sync_type)
    return if channel.provider_config.dig('coexistencia', sync_type).present?

    resposta = Whatsapp::FacebookApiClient.new(channel.provider_config['api_key'])
                                          .request_smb_app_data(channel.provider_config['phone_number_id'], sync_type)
    Whatsapp::Coexistencia.registrar!(channel, sync_type => { 'pedido_em' => Time.current.iso8601, 'request_id' => resposta&.dig('request_id') })
  end
end
