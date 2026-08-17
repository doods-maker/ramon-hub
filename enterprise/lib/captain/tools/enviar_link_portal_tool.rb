# Escrita "por rascunho": devolve o link magico do portal do cliente (upload de
# documentos) com uma frase pronta. O token nasce aqui se ainda nao existir —
# mesmo comportamento do botao "Link do portal" da ficha do lead.
class Captain::Tools::EnviarLinkPortalTool < Captain::Tools::RamonBaseTool
  SEM_URL = 'O link do portal nao esta configurado neste ambiente (FRONTEND_URL). Peca ao humano para enviar os documentos por aqui.'.freeze

  description 'Devolve o link do portal do cliente para ele enviar documentos pelo celular, com uma frase pronta. ' \
              'Nao envia sozinho: use o texto na resposta.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    base = ENV.fetch('FRONTEND_URL', '').strip
    return SEM_URL if base.blank?

    token = lead.ensure_portal_token!
    log_tool_usage('enviar_link_portal', { lead_id: lead.id })
    "Link do portal do cliente: #{base}/portal/#{token}\n" \
      "Frase sugerida: \"Para facilitar, voce pode enviar os documentos por este link seguro, direto do celular: #{base}/portal/#{token}\""
  end
end
