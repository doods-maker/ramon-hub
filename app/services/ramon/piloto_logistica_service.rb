# Piloto com limites (Onda C): decide se uma resposta do copiloto é PURA
# logística (cobrança de documento, confirmação de horário, mensagem de
# cadência) e portanto pode sair sozinha. Fail-safe: na dúvida ou em erro,
# false — a mensagem vira rascunho. DeepSeek sem json_schema (lição PR #110):
# JSON pedido no prompt + parse defensivo, padrão DocMatchService.
class Ramon::PilotoLogisticaService
  PROVIDER = 'deepseek'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você audita a resposta que um assistente de escritório de advocacia quer enviar a um cliente.
    Ela só pode sair sozinha se for PURA logística: pedir/cobrar documento, confirmar ou propor
    horário, saudação/lembrete curto de acompanhamento. Se contiver QUALQUER análise do caso,
    valor, honorário, prazo do INSS, promessa ou orientação jurídica, NÃO é logística.
    Responda APENAS um JSON válido (sem markdown): {"logistica": true} ou {"logistica": false}.
    Na dúvida, responda false.
  PROMPT

  def self.logistica?(texto)
    result = Ramon::LlmClient.complete(
      provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT, user: "Resposta a auditar:\n#{texto}"
    )
    parsed = JSON.parse(result.content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    parsed.is_a?(Hash) && parsed['logistica'] == true
  rescue StandardError => e
    Rails.logger.warn("[Ramon::PilotoLogisticaService] fail-safe rascunho (#{e.class}: #{e.message})")
    false
  end
end
