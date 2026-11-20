# Coexistência completa do WhatsApp (número que segue no app WhatsApp Business e também no hub).
# Estado em provider_config['coexistencia']: pedidos de sincronização, histórico recusado, desconexão.
module Whatsapp::Coexistencia
  # Trava a linha: o job de sincronização e os webhooks (history, account_update) escrevem no mesmo jsonb.
  # validate: false pula o validate_provider_config, que reconsulta a Meta (como Channel::Whatsapp#enable_voice_calling!).
  def self.registrar!(channel, dados)
    channel.with_lock do
      estado = (channel.provider_config['coexistencia'] || {}).merge(dados)
      channel.provider_config = channel.provider_config.merge('coexistencia' => estado)
      channel.save!(validate: false)
    end
  end
end
