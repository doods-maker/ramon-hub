# Envia um MetaEvento à API de Conversões. WABA e caixa vêm do clique (meta_referral); a conversa do lead é só reserva.
class Ramon::MetaConversaoJob < ApplicationJob
  queue_as :low

  retry_on Ramon::MetaCapi::Transitorio, wait: :polynomially_longer, attempts: 5 do |job, erro|
    job.arguments.first.then { |id| MetaEvento.find_by(id: id)&.update(status: 'erro', erro: erro.class.name.truncate(255)) }
  end

  def perform(meta_evento_id)
    evento = MetaEvento.find_by(id: meta_evento_id)
    return if evento.nil? || evento.status != 'pendente'

    lead = evento.lead
    referral = lead.custom_attributes.to_h['meta_referral'].to_h
    waba, token = credenciais(lead, referral)
    return encerrar(evento, 'ignorado', 'sem_waba') if waba.blank?
    return encerrar(evento, 'ignorado', 'sem_token') if token.blank?

    enviar(evento, lead, referral, waba, token)
  end

  private

  def enviar(evento, lead, referral, waba, token)
    Ramon::MetaCapi::Cliente.new(token: token, waba_id: waba).enviar(
      evento: evento.evento, event_id: evento.event_id, event_time: evento.ocorrido_em.to_i, ctwa_clid: referral['ctwa_clid'],
      value: (evento.evento == 'Purchase' ? lead.value&.to_f : nil)
    )
    evento.update!(status: 'enviado', enviado_em: Time.current, erro: nil)
  rescue Ramon::MetaCapi::Recusado => e
    encerrar(evento, 'erro', "#{e.class.name}: #{e.message}")
  end

  def encerrar(evento, status, erro)
    evento.update!(status: status, erro: erro.to_s.truncate(255))
  end

  # WABA e token saem do MESMO canal: o da caixa do clique ou, de reserva, o da conversa do lead.
  def credenciais(lead, referral)
    config = canal(lead, referral).try(:provider_config).to_h
    [referral['waba_id'].presence || config['business_account_id'], config['api_key']]
  end

  def canal(lead, referral)
    lead.account.inboxes.find_by(id: referral['inbox_id'])&.channel || lead.conversation&.inbox&.channel
  end
end
