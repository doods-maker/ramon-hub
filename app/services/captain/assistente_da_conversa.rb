# Quem responde a conversa (spec Etapa Documentos §2): o assistente da etapa do lead, se a etapa tem um e a chave
# RAMON_ETAPA_DOCUMENTOS está ligada; senão o da caixa (chave desligada = como antes do PR 2). Caixa sem IA = nil, mesmo
# com a etapa tendo assistente (a caixa do escritório fica com as pessoas). Todo ponto do atendimento que precisava de
# `inbox.captain_assistant` pergunta aqui. Fica no núcleo (Captain é enterprise: sem ele, sempre nil) para o CI, que roda
# sem enterprise/, carregar a classe.
module Captain::AssistenteDaConversa
  module_function

  def para(conversation)
    da_caixa = conversation.inbox.try(:captain_assistant)
    return da_caixa unless da_caixa && Ramon::EtapaDeGanho.documentos_ligado?

    lead = conversation.account.leads.find_by(conversation_id: conversation.id)
    lead&.lead_stage.try(:captain_assistant) || da_caixa
  end
end
