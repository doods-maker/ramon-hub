# Escrita "por rascunho": devolve o texto pronto do pedido de documentos para o
# Assistente colocar na resposta. Quem decide se sai (piloto) ou vira nota
# (rascunho) e o modo da conversa — a tool nao manda nada.
class Captain::Tools::SolicitarDocumentoTool < Captain::Tools::RamonBaseTool
  FALHA_DOSSIE = 'Nao consegui consultar os documentos do caso agora — tente de novo em instantes.'.freeze

  description 'Monta o texto pronto para pedir ao cliente os documentos que faltam no caso (ou uma lista informada). ' \
              'Devolve o texto para voce usar na resposta; nao envia sozinho.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :documentos, type: 'string', desc: 'Lista separada por virgula. Sem ela, usa os documentos pendentes da tese.', required: false

  def perform(tool_context, lead_id: nil, documentos: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    itens = lista(lead, documentos)
    return FALHA_DOSSIE if itens.nil?
    return "O caso #{lead.name} nao tem nenhum documento pendente." if itens.empty?

    log_tool_usage('solicitar_documento', { lead_id: lead.id, quantidade: itens.size })
    # ponytail: nao marca doc_status 'solicitado' — nao sabemos se o rascunho vai sair; o DocChecklist do humano marca.
    ["#{saudacao(lead)} Para dar andamento ao seu caso, ainda preciso destes documentos:",
     *itens.map { |d| "• #{d}" },
     'Pode mandar foto ou PDF por aqui mesmo. Assim que chegar, seguimos com o seu pedido. Obrigado!'].join("\n")
  end

  private

  # nil = a consulta ao dossie falhou (distinto de [] = consultou e nao ha pendencia).
  def lista(lead, documentos)
    informados = documentos.to_s.split(',').map(&:strip).reject(&:blank?)
    return informados if informados.any?

    Ramon::DossieService.new(lead: lead).perform.dig(:pendencias, :docs_missing).to_a.pluck(:title)
  rescue StandardError => e
    Rails.logger.warn("[solicitar_documento] dossie falhou: #{e.message}")
    nil
  end

  def saudacao(lead)
    nome = primeiro_nome(lead)
    nome ? "Ola #{nome}, tudo bem?" : 'Ola, tudo bem?'
  end

  def primeiro_nome(lead)
    lead.name.to_s.split.first
  end
end
