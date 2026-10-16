# Opções do passo do roteiro como botões ou lista no WhatsApp (decisão do Eduardo 15/10). Cada tese escolhe:
# desligado | ligado | teste_ab. No teste A/B, lead de id par recebe botões e ímpar recebe só texto. O grupo fica no lead
# (custom_attributes['roteiro_opcoes'] = botoes|texto) para o BI comparar.
# Só passo de escolha (até 10 opções, o máximo da lista do WhatsApp) ou de sim/não. O lead pode sempre responder digitando.
module Ramon::Roteiro::Opcoes
  BOTAO = 20 # título de botão do WhatsApp
  LINHA = 24 # título de linha da lista
  DESCRICAO = 72 # descrição da linha da lista
  MAX = 10 # linhas da lista
  CORPO = 1024 # corpo da mensagem interativa

  module_function

  # content_type e content_attributes da resposta da IA (Captain::Conversation::ResponseBuilderJob).
  def atributos(conversation, texto, content_attributes, handoff: false)
    itens = para_mensagem(conversation, texto) unless handoff
    return { content_type: 'text', content_attributes: content_attributes } if itens.nil?

    { content_type: 'input_select', content_attributes: content_attributes.merge('items' => itens) }
  end

  # Só no WhatsApp e quando a mensagem termina em pergunta; nil = só texto.
  def para_mensagem(conversation, texto)
    return unless conversation.inbox.channel.is_a?(Channel::Whatsapp)
    return unless texto.to_s.size <= CORPO && texto.to_s.strip.match?(/\?[^[:alnum:]]*\z/)

    itens(conversation.account.leads.find_by(conversation_id: conversation.id))
  end

  # Itens do input_select do passo atual do lead; nil = só texto.
  def itens(lead)
    return if lead&.thesis.nil? || grupo(lead) != 'botoes'

    opcoes = opcoes_do(Ramon::Roteiro.atual(lead)&.dig(:passo))
    opcoes&.map { |o| item(o, limite(opcoes)) }
  end

  def limite(opcoes) = opcoes.size <= 3 && opcoes.all? { |o| o.size <= BOTAO } ? BOTAO : LINHA

  def opcoes_do(passo)
    case passo&.tipo_resposta
    when 'escolha' then passo.opcoes if passo.opcoes.size.between?(1, MAX)
    when 'sim_nao' then %w[Sim Não]
    end
  end

  def item(opcao, limite)
    return { 'title' => opcao, 'value' => opcao } if opcao.size <= limite

    { 'title' => opcao.truncate(limite, separator: ' ', omission: '…'), 'value' => opcao, 'description' => opcao.truncate(DESCRICAO) }
  end

  def grupo(lead)
    case lead.thesis.opcoes_botoes
    when 'ligado' then marcar(lead, 'botoes')
    when 'teste_ab' then marcar(lead, lead.id.even? ? 'botoes' : 'texto')
    end
  end

  def marcar(lead, grupo)
    return grupo if lead.custom_attributes&.dig('roteiro_opcoes') == grupo

    lead.update_columns(custom_attributes: (lead.custom_attributes || {}).merge('roteiro_opcoes' => grupo)) # rubocop:disable Rails/SkipsModelValidations
    grupo
  end
end
