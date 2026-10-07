# B4.4 (spec §8): o que o hub faz quando o lead é ganho — dossiê de passagem, caso no ADVBOX e rascunho da pesquisa NPS —
# pelo código (como sempre) ou pelo fluxo "Lead ganho", conforme a chave (RAMON_FLUXO_LEAD_GANHO + o fluxo em modo normal).
# A decisão é do evento: lida UMA vez aqui e mandada no gatilho. Contrato fechado no ADVBOX também chega aqui (o evento
# move o lead para o ganho), pelo caminho que for — por isso nunca roda em dobro.
# Reserva (Eduardo, 07/10): fluxo no comando que NÃO começou este ganho (ocupado com o mesmo lead — execução anterior
# viva —, erro do motor, desligado no meio) → o código faz este ganho, como antes. O Drive fica no código
# (Lead#enqueue_drive_export: roda a cada atualização dos documentos, não só no ganho).
module Ramon::Fluxos::LeadGanho
  module_function

  def ganhou(lead)
    assumido = Ramon::Fluxos::Migracao.assumiu?(lead.account, 'lead_ganho')
    feitas = Ramon::Fluxos::Disparo.externo('lead_ganho', lead, { 'assumido' => assumido, 'para_etapa_id' => lead.lead_stage_id })
    # ponytail: ocupado = a execução viva (ADVBOX esperando nova tentativa) e o AdvboxClosingJob da reserva podem correr juntos — a
    # mesma janela de hoje com 2 ganhos seguidos (sincronizado_em + id guardado a cada passo); lock por lead se acontecer.
    pelo_codigo(lead) unless assumido && feitas.any?
  end

  # O caminho de hoje, como morava nos callbacks do Lead (e a reserva do fluxo). Na ordem em que os callbacks rodavam
  # (after_commit ao contrário): as 2 filas antes do dossiê — erro no dossiê não derruba o NPS nem o caso no ADVBOX.
  def pelo_codigo(lead)
    Ramon::NpsDraftJob.perform_later(lead.id)
    Ramon::AdvboxClosingJob.perform_later(lead.id) if ENV.fetch('ADVBOX_API_TOKEN', nil).present?
    Leads::HandoffNoteService.new(lead: lead).perform
  end
end
