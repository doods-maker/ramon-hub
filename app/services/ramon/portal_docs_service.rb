# As observações da tarefa "SOLICITAR DOCUMENTOS" do ADVBOX são prosa interna
# ("o juízo não aceita ZapSign… pedir comprovante de residência…"). O painel do
# cliente não pode mostrar isso cru: o LLM extrai só a lista de documentos que
# o CLIENTE precisa mandar, em nome curto pra leigo (decisão Eduardo 16/09).
# 1 chamada por tarefa; o PortalSyncService reaproveita enquanto o texto não muda.
class Ramon::PortalDocsService
  PROVIDER = 'deepseek'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você recebe as observações internas de uma tarefa "SOLICITAR DOCUMENTOS" de um escritório de advocacia previdenciária.
    Liste APENAS os documentos que o CLIENTE precisa enviar ou providenciar. Cada item é um nome curto e claro para leigo,
    começando em maiúscula (ex.: "Comprovante de residência atual em seu nome"). Se um documento só é preciso numa condição,
    inclua a condição curta entre parênteses (ex.: "Certidão de casamento (se o comprovante estiver no nome da esposa)").
    Ignore instruções da equipe, comentários sobre o juízo, sistemas ou prazos. Não invente documentos que o texto não pede.
    Responda APENAS um JSON válido, sem markdown: {"documentos": ["..."]}. Sem documentos pedidos → {"documentos": []}.
  PROMPT

  # Devolve a lista de nomes; nil quando o LLM falhou (o sync então não grava
  # nada pra esse pedido e tenta de novo na próxima noite).
  def self.itens(notes, nome: nil)
    texto = notes.to_s.strip
    return [] if texto.blank?

    result = Ramon::LlmClient.complete(
      provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT, user: Ramon::Pseudonymizer.mask(texto, names: [nome].compact)
    )
    parse(result.content)
  rescue StandardError => e
    Rails.logger.warn("[Ramon::PortalDocsService] falhou: #{e.class}: #{e.message}")
    nil
  end

  def self.parse(content)
    parsed = JSON.parse(content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    lista = parsed.is_a?(Hash) ? parsed['documentos'] : parsed
    return nil unless lista.is_a?(Array)

    lista.map { |d| d.to_s.squish.first(120) }.compact_blank.uniq
  rescue JSON::ParserError
    nil
  end
end
