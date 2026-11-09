# Senha (gov.br e afins) nunca vai a LLM: Message#content_for_llm passa por aqui,
# então vale para todo transcript (copiloto, colheita, resumo, IA que atende),
# inclusive o caminho sem pseudonimização. A regra do texto mora no Pseudonymizer.
module Ramon::SenhaForaDaIa
  module_function

  def para_llm(message, texto)
    return Ramon::Pseudonymizer::SENHA_MASCARA if solta?(message)

    texto && Ramon::Pseudonymizer.sem_senha(texto)
  end

  # Senha mandada sozinha ("Tx9#kLm2") logo depois de uma mensagem que fala em senha.
  # Só consulta a anterior quando a mensagem já tem cara de senha (raro).
  def solta?(message)
    return false unless message.incoming? && message.created_at
    return false unless Ramon::Pseudonymizer.senha_provavel?(message.content.to_s.strip)

    anterior = Message.where(conversation_id: message.conversation_id, message_type: [:incoming, :outgoing], private: false)
                      .where(created_at: ...message.created_at).order(created_at: :desc).pick(:content)
    anterior.to_s.match?(Ramon::Pseudonymizer::SENHA)
  end
end
