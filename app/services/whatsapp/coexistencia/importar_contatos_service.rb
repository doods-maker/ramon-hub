# Webhook `smb_app_state_sync` da coexistência: a agenda de contatos do app WhatsApp Business. Entra em
# silêncio (Ramon::Silencio). `add` cria ou completa o contato; `remove` não apaga nada do hub.
class Whatsapp::Coexistencia::ImportarContatosService
  def initialize(channel:, value:)
    @channel = channel
    @inbox = channel.inbox
    @value = value.with_indifferent_access
  end

  def perform
    Ramon::Silencio.executar { Array(@value[:state_sync]).each { |item| importar(item) } }
  end

  private

  def importar(item)
    return unless item[:type] == 'contact'

    dados = item[:contact] || {}
    telefone = Whatsapp::Coexistencia.telefone(dados[:phone_number])
    return if telefone.blank?
    return Rails.logger.info("[WHATSAPP] Coexistencia: contato removido no app (canal #{@channel.id}), mantido no hub") if item[:action] == 'remove'

    contato = Whatsapp::Coexistencia.contact_inbox!(@inbox, telefone, dados[:full_name]).contact
    completar_nome(contato, dados[:full_name], telefone)
  end

  # Nome editado no hub manda: só troca quando o atual está vazio ou é o próprio telefone.
  def completar_nome(contato, nome, telefone)
    return if nome.blank? || contato.name == nome
    return unless contato.name.blank? || contato.name.delete('^0-9') == telefone

    contato.update!(name: nome)
  end
end
