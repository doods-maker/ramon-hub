# Tese automática do lead (spec roteiro §3.6, F3). Na 1ª mensagem do cliente, lead sem tese ganha a tese pela
# palavra-chave — na campanha da LP (lead.source, ex. "t-auxilio-acidente"), no texto da mensagem ou no título do
# anúncio da Meta — e, sem palavra, pela tese padrão da caixa. Sem nada, o passo comum "assunto" do roteiro pergunta.
# Também casa a resposta do "assunto" (Ramon::Roteiro::Registro). Tese nunca é trocada aqui.
module Ramon::TeseAutomatica
  module_function

  def definir(lead, message)
    return if lead.thesis_id || !primeira?(message)

    titulo_anuncio = Ramon::LeadDaConversa.referral_da(message)&.dig('headline')
    # Tese padrão da caixa sempre buscada na conta do lead: inboxes.ramon_thesis_id não é validado contra a conta.
    tese = por_texto(lead.account, lead.source, message.content, titulo_anuncio) ||
           lead.account.theses.find_by(id: message.inbox&.ramon_thesis_id)
    lead.update!(thesis: tese) if tese
  end

  # Palavra ou frase inteira, sem acento nem caixa, contra palavras-chave e nome das teses ativas.
  # Duas teses casando = ambíguo = nil (tese errada é pior que nenhuma).
  def por_texto(account, *textos)
    alvo = " #{textos.map { |texto| normal(texto) }.join(' ')} "
    achadas = account.theses.where(active: true).select do |tese|
      (tese.palavras_chave + [tese.name]).any? { |termo| casa?(alvo, normal(termo)) }
    end
    achadas.first if achadas.one?
  end

  def casa?(alvo, termo) = termo.present? && alvo.include?(" #{termo} ")

  def primeira?(message)
    message.conversation.messages.incoming.where(id: ...message.id).none?
  end

  def normal(texto)
    I18n.transliterate(texto.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end
end
