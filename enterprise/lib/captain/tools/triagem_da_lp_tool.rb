# Leitura pura: o quiz que o lead respondeu na landing page antes de chamar no
# WhatsApp (chega em `lead.custom_attributes['quiz']` pelo endpoint publico).
# Para o agente nao perguntar de novo o que a pessoa ja respondeu na LP.
class Captain::Tools::TriagemDaLpTool < Captain::Tools::RamonBaseTool
  description 'Triagem que o lead fez na landing page: veredito (qualificado ou nao), cada pergunta com a ' \
              'resposta dada, duvidas marcadas e a campanha de origem. Use antes de qualificar quem veio da LP ' \
              'para nao repetir perguntas ja respondidas.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    log_tool_usage('triagem_da_lp', { lead_id: lead.id })
    quiz = lead.custom_attributes&.dig('quiz')
    return "Caso ##{lead.id}: sem triagem da landing page (a pessoa nao passou pelo quiz)." if quiz.blank?

    [cabecalho(lead, quiz), respostas(quiz), duvidas(quiz)].compact.join("\n\n")
  rescue StandardError => e
    Rails.logger.error("TriagemDaLpTool: #{e.class}: #{e.message}")
    'Nao consegui ler a triagem da LP agora. Siga sem ela.'
  end

  private

  def cabecalho(lead, quiz)
    veredito = quiz['qualificado'] == true ? 'QUALIFICADO pelo quiz' : 'NAO qualificado pelo quiz'
    "Triagem da LP do caso ##{lead.id} (#{lead.name}): #{veredito} | campanha: #{lead.source.presence || '-'} | " \
      "em #{data(quiz['em'])}"
  end

  def respostas(quiz)
    lista = Array.wrap(quiz['respostas'])
    return 'Respostas: nenhuma.' if lista.empty?

    linhas = lista.map do |r|
      marca = [(' [REPROVA]' if r['reprova']), (' [DUVIDA]' if r['duvida'])].compact.join
      "- #{r['pergunta']}: #{r['resposta']}#{marca}"
    end
    "Respostas (#{lista.size}):\n#{linhas.join("\n")}"
  end

  def duvidas(quiz)
    lista = Array.wrap(quiz['duvidas'])
    return nil if lista.empty?

    "Duvidas que a pessoa marcou (esclarecer na conversa):\n#{lista.map { |d| "- #{d}" }.join("\n")}"
  end

  def data(iso)
    Time.zone.parse(iso.to_s)&.in_time_zone('America/Sao_Paulo')&.strftime('%d/%m/%Y') || '-'
  rescue ArgumentError
    '-'
  end
end
