# Passo da reunião cancelada (B4.1): apaga a(s) tarefa(s) de reunião do evento — as que o painel ou o Cal.com mandaram
# no gatilho ('tarefa_ids'), só do próprio lead. Apagar a tarefa também encerra o ciclo de lembretes dela (alvo apagado).
module Ramon::Fluxos::Passos::Reuniao
  module_function

  def apagar_reuniao(_config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    ids = Array(ctx.gatilho('tarefa_ids')).map(&:to_i).sort
    return { saida: 's', resumo: "faria: apagar tarefas #{lista(ids)}" } if ctx.ensaio?

    apagadas = lead.lead_tasks.where(id: ids, kind: 'meeting').destroy_all.map(&:id).sort
    { saida: 's', resumo: "apagou tarefas #{lista(apagadas)}" }
  end

  # "#12, #13" ou "(nenhuma)" (também usado pela comparação do agendamento)
  def lista(ids) = ids.any? ? ids.map { |id| "##{id}" }.join(', ') : '(nenhuma)'
end
