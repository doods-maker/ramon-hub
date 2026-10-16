# Opções do passo do roteiro como botões ou lista no WhatsApp (decisão do Eduardo 15/10). Cada tese escolhe um modo de
# Thesis::OPCOES_BOTOES. No teste A/B, lead de id par recebe botões e ímpar recebe só texto. O grupo fica no lead
# (custom_attributes['roteiro_opcoes'] = botoes|texto; bi_roteiro.opcoes_grupo) só durante o teste, para o BI comparar.
# Só passo de escolha (até 10 opções, o máximo da lista do WhatsApp) ou de sim/não, e só quando a pergunta da mensagem
# é a do roteiro: a IA viu o passo neste turno (passo_mostrado, das tools do roteiro), pergunta só ele e ele não é
# "sem perguntar". O lead pode sempre responder digitando.
module Ramon::Roteiro::Opcoes
  BOTAO = Whatsapp::Providers::BaseService::BOTAO_MAX
  LINHA = 24 # título de linha da lista
  DESCRICAO = 72 # descrição da linha da lista
  MAX = 10 # linhas da lista
  CORPO = 1024 # corpo da mensagem interativa

  module_function

  # content_type e content_attributes da resposta da IA (Captain::Conversation::ResponseBuilderJob).
  # resposta = a do AgentRunnerService; 'roteiro_passo' = chave do último passo que as tools do roteiro mostraram à IA
  # neste turno (nil = nenhum).
  def atributos(conversation, texto, content_attributes, resposta, handoff: false)
    itens = para_mensagem(conversation, texto, resposta&.dig('roteiro_passo')) unless handoff
    return { content_type: 'text', content_attributes: content_attributes } if itens.nil?

    { content_type: 'input_select', content_attributes: content_attributes.merge('items' => itens) }
  end

  # Só no WhatsApp e quando a mensagem termina em pergunta; nil = só texto.
  def para_mensagem(conversation, texto, passo_mostrado)
    return unless conversation.inbox.channel.is_a?(Channel::Whatsapp)
    return unless texto.to_s.size <= CORPO && texto.to_s.strip.match?(/\?[^[:alnum:]]*\z/)

    botoes(conversation.account.leads.find_by(conversation_id: conversation.id), passo_mostrado)
  end

  # Os botões da pergunta do passo atual do lead; nil = só texto.
  def botoes(lead, passo_mostrado)
    opcoes = opcoes_da_pergunta(lead, passo_mostrado)
    return if opcoes.nil? || !recebe_botoes!(lead)

    opcoes.map { |o| item(o, limite(opcoes)) }
  end

  # As opções do passo que a IA pergunta: o mostrado a ela neste turno, sozinho na mensagem e que não é "sem perguntar".
  def opcoes_da_pergunta(lead, passo_mostrado)
    return if lead&.thesis.nil? || passo_mostrado.nil?

    passo = passo_sozinho(lead)
    opcoes_do(passo) if passo && passo.chave == passo_mostrado && !passo.sem_perguntar
  end

  # O passo atual, se a IA pergunta só ele: com "Pode perguntar junto" a mensagem leva 2 perguntas e vai só em texto.
  def passo_sozinho(lead)
    atual = Ramon::Roteiro.atual(lead)
    passo = atual&.dig(:passo)
    passo unless passo.nil? || Ramon::Roteiro.junto(passo, atual[:estado])
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

  # O lead recebe botões? O "!" avisa que grava: no teste A/B, a 1ª pergunta com botões possíveis grava o grupo do
  # lead, e ele não troca depois (a tese sair do teste não apaga o histórico do A/B). Modo desconhecido = só texto.
  def recebe_botoes!(lead)
    case lead.thesis.opcoes_botoes
    when 'ligado' then true
    when 'teste_ab' then grupo_ab!(lead) == 'botoes'
    else false
    end
  end

  def grupo_ab!(lead)
    salvo = lead.custom_attributes['roteiro_opcoes']
    return salvo if salvo

    grupo = lead.id.even? ? 'botoes' : 'texto'
    lead.update_columns(custom_attributes: lead.custom_attributes.merge('roteiro_opcoes' => grupo)) # rubocop:disable Rails/SkipsModelValidations
    grupo
  end
end
