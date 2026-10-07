# FAQ a partir das conversas (Inteligência A4) — as peças sem Captain, que o CI testa:
#   - de_mensagem: "Virar FAQ" (I-X1) — a pergunta é o que o lead escreveu logo antes da resposta. SEM IA.
#   - texto + PROMPT: o que vai ao LLM na geração das conversas resolvidas (I-X2). Só as MENSAGENS (sem cabeçalho nem
#     "Conversation Attributes": atributos podem guardar nome/PII fora do corte), sem notas privadas, mascaradas e cortadas.
#   - pausada?: a geração automática para no dia em que o gasto chega ao teto do alerta (tela Uso e custo).
# LGPD: pergunta, resposta e conversa passam pelo Ramon::Pseudonymizer (nome do contato e do lead, CPF, RG,
# telefone, e-mail, CEP, endereço viram [marcador]); quem aprova a FAQ ajusta o texto.
# A FAQ nasce PENDENTE e o assistente só lê as aprovadas (faq_lookup_tool.rb: .approved.search).
module Ramon::FaqDeConversa
  class Recusa < StandardError; end

  LIMITE_CONVERSA = 8_000 # caracteres do fim da conversa (mesmo teto dos passos de IA dos fluxos)
  LIMITE_PERGUNTA = 500
  PROMPT = <<~TXT.freeze
    Você lê uma conversa de WhatsApp entre um escritório de advocacia previdenciária e trabalhista (Support Agent)
    e um lead (User), e transforma em FAQs curtas o que pode servir para OUTROS leads.
    Responda APENAS JSON válido, sem markdown: {"faqs": [{"question": "...", "answer": "..."}]}.
    Regras:
    - Só perguntas que o lead fez e que o atendente (Support Agent) respondeu; ignore o que o Bot escreveu.
    - Pergunta genérica, como outro lead perguntaria; resposta curta, só com o que o atendente disse.
    - Nada do caso concreto: sem nome, CPF, telefone, endereço, datas ou valores da pessoa; não copie marcadores como [nome].
    - Nunca prometa resultado nem prazo do INSS ou da Justiça.
    - Honorário só se o atendente falou, e sempre como 30% dos atrasados + 3 parcelas do benefício.
    - No máximo 3 FAQs. Se nada servir para outros leads, responda {"faqs": []}.
    - Escreva em português do Brasil.
  TXT

  module_function

  def de_mensagem(mensagem)
    raise Recusa, 'SEM_RESPOSTA' unless mensagem.outgoing? && !mensagem.private? && mensagem.content.present?

    pergunta = pergunta_antes(mensagem)
    raise Recusa, 'SEM_PERGUNTA' if pergunta.blank?

    nomes = nomes(mensagem.conversation)
    { question: Ramon::Pseudonymizer.mask(pergunta, names: nomes).truncate(LIMITE_PERGUNTA),
      answer: Ramon::Pseudonymizer.mask(mensagem.content, names: nomes) }
  end

  # As bolhas do lead entre a resposta anterior enviada (nota privada não conta) e esta.
  def pergunta_antes(mensagem)
    mensagens = mensagem.conversation.messages
    anterior = mensagens.where(message_type: :outgoing, private: false, id: ...mensagem.id).reorder(id: :desc).pick(:id) || 0
    bolhas = mensagens.where(message_type: :incoming, id: (anterior + 1)...mensagem.id)
    bolhas.reorder(:id).pluck(:content).compact_blank.join("\n")
  end

  # Só mensagens, do fim para o começo, mensagem inteira ou nada (não corta no meio); depois mascara.
  def texto(conversa)
    linhas = []
    total = 0
    mensagens_publicas(conversa).each do |mensagem|
      texto_linha = linha(mensagem)
      break if total + texto_linha.length > LIMITE_CONVERSA

      linhas.prepend(texto_linha)
      total += texto_linha.length
    end
    Ramon::Pseudonymizer.mask(linhas.join, names: nomes(conversa)).last(LIMITE_CONVERSA)
  end

  def mensagens_publicas(conversa)
    conversa.messages.where(private: false).where.not(message_type: %i[activity template])
            .reorder(id: :desc).limit(LIMITE_CONVERSA)
  end

  def linha(mensagem)
    autor = { 'User' => 'Support Agent', 'Contact' => 'User' }.fetch(mensagem.sender_type, 'Bot')
    "#{autor}: #{mensagem.content_for_llm}\n"
  end

  def pausada?(account)
    teto = Ramon::IaGastoAlerta.teto(account)
    teto.to_f.positive? && Ramon::IaGastoAlerta.gasto_hoje(account.id) >= teto
  end

  def nomes(conversa)
    [conversa.contact&.name, conversa.account.leads.find_by(conversation_id: conversa.id)&.name]
  end
end
