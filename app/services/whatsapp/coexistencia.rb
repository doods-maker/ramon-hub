# Coexistência completa do WhatsApp (número que segue no app WhatsApp Business e também no hub).
# Estado em provider_config['coexistencia']: pedidos de sincronização, histórico recusado, desconexão.
module Whatsapp::Coexistencia
  # Marca da conversa e das mensagens importadas (additional_attributes / content_attributes).
  MARCA = 'importado_coexistencia'.freeze

  # Trava a linha: o job de sincronização e os webhooks (history, account_update) escrevem no mesmo jsonb.
  # validate: false pula o validate_provider_config, que reconsulta a Meta (como Channel::Whatsapp#enable_voice_calling!).
  def self.registrar!(channel, dados)
    channel.with_lock do
      estado = (channel.provider_config['coexistencia'] || {}).merge(dados)
      channel.provider_config = channel.provider_config.merge('coexistencia' => estado)
      channel.save!(validate: false)
    end
  end

  # Mesmo caminho do incoming normal (normalização BR/AR do source_id + ContactInboxWithContactBuilder, que
  # reaproveita contato pelo telefone), sem passar pelo serviço de mensagem, que dispara lead e IA.
  def self.contact_inbox!(inbox, telefone, nome)
    source_id = Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(telefone, :cloud)
    ContactInboxSourceIdResolver.new(
      inbox: inbox, source_ids: [source_id], contact_attributes: { name: nome.presence || "+#{telefone}", phone_number: "+#{telefone}" }
    ).perform
  end

  # Telefone em dígitos, até 15 (E.164); aceita "+", espaço, hífen e parênteses. BSUID ("BR.123...") não vira contato.
  def self.telefone(valor)
    digitos = valor.to_s.delete(' +()-')
    digitos if digitos.match?(/\A\d{1,15}\z/)
  end
end
