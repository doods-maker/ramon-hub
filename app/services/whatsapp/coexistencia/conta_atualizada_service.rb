# Webhook `account_update` da coexistência. Não traz metadata: o canal sai do WABA id (waba_info.waba_id,
# ou entry[0].id nos eventos sem waba_info). Desconexão só grava e avisa no ntfy — sem e-mail e sem
# prompt_reauthorization!, porque reconectar é refazer o Embedded Signup pela caixa.
class Whatsapp::Coexistencia::ContaAtualizadaService
  DESCONEXAO = %w[PARTNER_REMOVED ACCOUNT_OFFBOARDED].freeze

  def initialize(params)
    @params = params.with_indifferent_access
    @value = @params.dig(:entry, 0, :changes, 0, :value) || {}
    @evento = @value[:event]
  end

  def perform
    Rails.logger.info("[WHATSAPP] Coexistencia: account_update #{@evento} sem canal no hub (WABA #{waba_id})") if canais.empty?

    canais.each do |channel|
      if DESCONEXAO.include?(@evento)
        desconectar(channel)
      elsif @evento == 'ACCOUNT_RECONNECTED'
        Whatsapp::Coexistencia.registrar!(channel, 'desconectado_em' => nil)
        Rails.logger.info("[WHATSAPP] Coexistencia: canal #{channel.id} reconectado")
      else
        Rails.logger.info("[WHATSAPP] Coexistencia: account_update #{@evento} no canal #{channel.id}")
      end
    end
  end

  private

  def waba_id
    @value.dig(:waba_info, :waba_id).presence || @params.dig(:entry, 0, :id)
  end

  def canais
    return [] if waba_id.blank?

    @canais ||= Channel::Whatsapp.where(provider: 'whatsapp_cloud').where("provider_config ->> 'business_account_id' = ?", waba_id.to_s).to_a
  end

  def desconectar(channel)
    motivo = @value.dig(:disconnection_info, :reason) || @evento
    Whatsapp::Coexistencia.registrar!(channel, 'desconectado_em' => Time.current.iso8601, 'motivo' => motivo,
                                               'iniciado_por' => @value.dig(:disconnection_info, :initiated_by))
    Ramon::NtfyPushJob.perform_later(title: 'WhatsApp desconectado do hub', body: "WhatsApp desconectado do hub (#{motivo}) — reconectar pela caixa")
  end
end
