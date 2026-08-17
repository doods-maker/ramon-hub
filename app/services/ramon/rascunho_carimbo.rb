# Carimbo "veio de rascunho da IA" (spec Inteligencia, Onda 3): quando o humano
# manda uma mensagem publica e existe uma nota-rascunho do Assistente depois da
# ultima fala do cliente, a mensagem ganha content_attributes.ramon_rascunho_ia
# com o desfecho — base da metrica bi_ia (D8) e da decisao D7 (piloto por padrao).
module Ramon::RascunhoCarimbo
  PREFIXO = 'RASCUNHO (revisar antes de enviar):'.freeze
  CHAVE = 'ramon_rascunho_ia'.freeze

  module_function

  def candidata?(message)
    message.outgoing? && !message.private? && message.sender_type == 'User' && message.content.present?
  end

  # Muta content_attributes da mensagem AINDA NAO salva (before_create) — sem update extra.
  def aplicar(message)
    nota = nota_elegivel(message.conversation)
    return if nota.blank?

    texto_nota = normal(nota.content.delete_prefix(PREFIXO))
    sim = similaridade(texto_nota, message.content)
    desfecho = desfecho_de(texto_nota, message.content, sim)
    message.content_attributes = message.content_attributes.merge(
      CHAVE => { 'nota_id' => nota.id, 'desfecho' => desfecho, 'similaridade' => sim.round(2) }
    )
  end

  def desfecho_de(texto_nota_normal, texto_msg, sim)
    return 'igual' if texto_nota_normal == normal(texto_msg)
    return 'editado' if sim >= 0.3

    'descartado'
  end

  # A ultima nota-rascunho e a mais NOVA criada depois da ultima fala do cliente
  # (reorder pisa no default_scope asc do Message — sem isso o .order gruda no
  # asc e devolve a mais antiga).
  def nota_elegivel(conversation)
    ultima_do_cliente = conversation.messages.incoming.maximum(:created_at)
    notas = conversation.messages.where(private: true, sender_type: 'Captain::Assistant')
                        .where('content LIKE ?', "#{PREFIXO}%")
    notas = notas.where('created_at > ?', ultima_do_cliente) if ultima_do_cliente
    notas.reorder(created_at: :desc).first
  end

  def normal(texto) = texto.to_s.downcase.gsub(/\s+/, ' ').strip

  # ponytail: Jaccard de palavras (>=3 letras); se confundir editado x descartado, trocar por Levenshtein.
  def similaridade(a, b)
    pa = palavras(a)
    pb = palavras(b)
    return 0.0 if pa.empty? || pb.empty?

    (pa & pb).size.to_f / (pa | pb).size
  end

  def palavras(texto) = I18n.transliterate(normal(texto)).scan(/[a-z0-9]{3,}/).uniq
end
