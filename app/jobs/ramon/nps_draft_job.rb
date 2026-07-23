# NPS pós-encerramento (mapa comercial 23/07): rascunho de pesquisa 0-10 +
# pedido de avaliação no Google. Fase 'comercial' (fechamento do lead) grava
# nps.pedido_em; fase 'exito' (fim do processo, via AdvBox) grava
# nps.pedido_exito_em — cada fase pede uma vez só.
class Ramon::NpsDraftJob < ApplicationJob
  queue_as :low

  GUARD_KEYS = { 'comercial' => 'pedido_em', 'exito' => 'pedido_exito_em' }.freeze

  def perform(lead_id, fase: 'comercial')
    lead = Lead.find_by(id: lead_id)
    return if lead.blank?

    guard_key = GUARD_KEYS.fetch(fase)
    return if lead.custom_attributes.dig('nps', guard_key).present?

    lead.lead_notes.create!(account: lead.account, body: note_body(lead).truncate(1000))
    register(lead, guard_key)
  end

  private

  def note_body(lead)
    first = lead.name.to_s.split.first.presence || 'cliente'
    review = ENV.fetch('RAMON_GOOGLE_REVIEW_URL', nil).presence || '[link do Google Meu Negócio]'
    <<~NOTA.strip
      RASCUNHO (revisar antes de enviar) — pesquisa NPS:
      "#{first}, de 0 a 10, que nota você dá pro nosso atendimento até aqui? Sua opinião ajuda a gente a melhorar de verdade.
      E se a experiência foi boa, sua avaliação no Google ajuda outras pessoas a nos encontrarem: #{review}"
    NOTA
  end

  # lição lost update: reload antes do merge; escrever SÓ a chave nps.
  def register(lead, guard_key)
    lead.reload
    nps = (lead.custom_attributes['nps'] || {}).merge(guard_key => Time.current.iso8601)
    lead.update!(custom_attributes: lead.custom_attributes.merge('nps' => nps))
  end
end
