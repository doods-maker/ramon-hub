# "Perguntar ao AdvBox": responde perguntas do atendente sobre os processos do
# cliente da conversa, com dados vivos do AdvBox (processos, andamentos e
# publicações) + DeepSeek. O contexto do AdvBox vai e volta no
# follow_up_context (stateless) para a conversa continuar sem rebuscar.
# LGPD: o texto sai pseudonimizado (mesmo padrão do ConversationCopilotService).
class Ramon::AdvboxPerguntaService
  class SemClienteError < StandardError; end
  class SemProcessoError < StandardError; end

  MAX_PROCESSOS = 5
  MAX_ANDAMENTOS = 8
  MAX_PUBLICACOES = 2
  TAMANHO_PUBLICACAO = 500
  PROVIDER = 'deepseek'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o assistente processual de um escritório de advocacia previdenciária e
    trabalhista no Brasil. Receberá dados do sistema de gestão (AdvBox): os
    processos de um cliente, com fase, andamentos recentes e publicações.
    Responda à pergunta do atendente em português do Brasil, curto e objetivo.
    Cite o número do processo ao afirmar algo sobre ele. Não invente: se a
    informação não estiver nos dados, diga que não consta no AdvBox.
    Dados pessoais aparecem mascarados como [nome], [cpf], [telefone] — mantenha
    os marcadores como estão.
  PROMPT

  PANORAMA = 'Dê um panorama dos processos deste cliente: para cada um, fase atual e último andamento.'.freeze

  def initialize(conversation, pergunta: nil, contexto: nil, historico: [])
    @conversation = conversation
    @pergunta = pergunta.presence || PANORAMA
    @contexto = contexto
    @historico = Array(historico).last(6)
    @lead = conversation.account.leads.find_by(conversation_id: conversation.id)
  end

  def perform
    @contexto ||= montar_contexto
    result = Ramon::LlmClient.complete(
      provider: PROVIDER,
      model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT,
      user: user_prompt
    )
    {
      message: restore_name(result.content),
      follow_up_context: {
        'advbox' => true,
        'contexto' => @contexto,
        'historico' => @historico + [{ 'pergunta' => @pergunta,
                                       'resposta' => result.content }]
      }
    }
  end

  private

  def nome_cliente
    @nome_cliente ||= (@lead&.name.presence || @conversation.contact&.name).to_s.strip
  end

  def montar_contexto
    raise SemClienteError, 'Conversa sem contato/lead com nome para buscar no AdvBox' if nome_cliente.blank?

    processos = Ramon::AdvboxClient.lawsuits(name: nome_cliente)['data'].to_a.first(MAX_PROCESSOS)
    raise SemProcessoError, "Nenhum processo no AdvBox para \"#{nome_cliente}\"" if processos.empty?

    blocos = processos.map { |p| bloco_processo(p) }
    mascarar("Cliente: #{nome_cliente}\n\n#{blocos.join("\n\n")}")
  end

  def bloco_processo(processo)
    linhas = ["Processo #{processo['process_number'] || "id #{processo['id']}"}",
              "Tipo: #{processo['type']} (#{processo['group']})",
              "Fase: #{processo['stage']} · Etapa: #{processo['step']}",
              "Responsável: #{processo['responsible']}"]
    linhas << "Partes: #{processo['customers'].to_a.pluck('name').join(' × ')}"
    linhas << andamentos_de(processo['id'])
    linhas << publicacoes_de(processo['id'])
    linhas.compact.join("\n")
  end

  def andamentos_de(lawsuit_id)
    movs = Ramon::AdvboxClient.movements(lawsuit_id, limit: MAX_ANDAMENTOS)['data'].to_a
    return nil if movs.empty?

    itens = movs.map { |m| "- #{m['date']}: #{m['title']} (#{m['header']})" }
    "Andamentos recentes:\n#{itens.join("\n")}"
  end

  def publicacoes_de(lawsuit_id)
    pubs = Ramon::AdvboxClient.publications(lawsuit_id, limit: MAX_PUBLICACOES)['data'].to_a
    return nil if pubs.empty?

    itens = pubs.map do |p|
      texto = p['publication'].to_s.gsub(/\s+/, ' ').truncate(TAMANHO_PUBLICACAO)
      "- #{p['start']}: #{texto}"
    end
    "Publicações recentes:\n#{itens.join("\n")}"
  end

  def user_prompt
    partes = [@contexto]
    @historico.each do |h|
      partes << "Pergunta anterior: #{h['pergunta']}\nResposta anterior: #{h['resposta']}"
    end
    partes << "Pergunta do atendente: #{mascarar(@pergunta)}"
    partes.join("\n\n")
  end

  def mascarar(texto)
    Ramon::Pseudonymizer.mask(texto, names: [nome_cliente, @conversation.contact&.name])
  end

  def restore_name(content)
    primeiro = nome_cliente.split.first
    return content if primeiro.blank?

    content.gsub('[nome]', primeiro)
  end
end
