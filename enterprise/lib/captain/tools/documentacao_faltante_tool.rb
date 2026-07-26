# Leitura pura: o que ainda falta no caso — documentos da checklist da tese,
# lacunas que a colheita nao conseguiu preencher e tarefas em aberto. Reusa o
# mesmo calculo do Dossie (checklist da tese x custom_attributes.doc_status).
class Captain::Tools::DocumentacaoFaltanteTool < Captain::Tools::RamonBaseTool
  description 'Lista o que ainda falta no caso: documentos pendentes da checklist da tese, lacunas da colheita ' \
              '(dados que ninguem informou ainda) e tarefas em aberto. Use antes de reuniao ou de fechar contrato.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    log_tool_usage('documentacao_faltante', { lead_id: lead.id })
    pendencias = ::Ramon::DossieService.new(lead: lead).perform[:pendencias]
    resposta(lead, pendencias).to_json
  end

  private

  def resposta(lead, pendencias)
    {
      lead_id: lead.id,
      nome: lead.name,
      tese: lead.thesis&.name,
      documentos_pendentes: pendencias[:docs_missing],
      tarefas_abertas: pendencias[:tasks],
      lacunas_da_colheita: colheita(lead, 'lacunas'),
      a_confirmar: colheita(lead, 'confirmar')
    }
  end

  def colheita(lead, chave)
    lead.custom_attributes&.dig('colheita', chave) || []
  end
end
