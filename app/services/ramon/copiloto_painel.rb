# Painel do Copiloto na conversa (Inteligência A4 — I-X3): o que o agente da equipe recebe do caso aberto.
# LGPD: só a data de hoje, o nº da conversa, o nº do caso (lead_id — as skills usam "caso N") e o nome do
# cliente (a busca de processo no AdvBox precisa dele). CPF, telefone, documentos e o texto da conversa NÃO vão:
# as skills buscam o que precisam pelas ferramentas, como no Testar.
module Ramon::CopilotoPainel
  module_function

  def contexto(account, display_id, user)
    hoje = Time.find_zone!(Ramon::CockpitMetrics::TIME_ZONE).today.strftime('%d/%m/%Y')
    conversa = conversa_visivel(account, display_id, user)
    return "Contexto: hoje é #{hoje}; nenhuma conversa aberta na tela." if conversa.nil?

    lead = account.leads.find_by(conversation_id: conversa.id)
    nome = nome_cliente(lead, conversa)
    caso = rotulo_caso(lead)
    "Contexto: hoje é #{hoje}; a equipe está com a conversa ##{conversa.display_id} aberta — #{caso}, cliente #{nome}. " \
      '"Este cliente" ou "este caso" é este.'
  end

  # Contexto na frente só da última pergunta da pessoa (o que vai ao agente); o histórico salvo não muda.
  def com_contexto(historico, account, display_id, user)
    ultima = historico.rindex { |item| item[:role].to_s == 'user' }
    return historico if ultima.nil?

    historico.each_with_index.map do |item, indice|
      indice == ultima ? item.merge(content: "#{contexto(account, display_id, user)}\n\n#{item[:content]}") : item
    end
  end

  # Admin vê qualquer conversa da conta; agente só as das caixas dele (o job roda no Sidekiq: sem Current.user/account).
  def conversa_visivel(account, display_id, user)
    return if display_id.blank? || user.nil?

    conversas = account.conversations
    admin = user.account_users.find_by(account_id: account.id)&.administrator?
    conversas = conversas.where(inbox_id: user.inboxes.select(:id)) unless admin
    conversas.find_by(display_id: display_id)
  end

  def nome_cliente(lead, conversa)
    (lead&.name.presence || conversa.contact&.name).to_s.strip.presence || 'sem nome'
  end

  def rotulo_caso(lead)
    lead ? "caso #{lead.id} do hub (lead_id=#{lead.id})" : 'sem caso no hub'
  end
end
