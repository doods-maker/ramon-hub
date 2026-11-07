# Canal de cada mensagem da cobrança da etapa Documentos (spec Etapa Documentos §7), decidido na hora do envio: só a janela de
# 24 h do canal dá permissão (Conversations::MessageWindowService; a janela grátis de anúncio muda só o preço). Dentro dela, o
# texto aprovado do passo; fora, o modelo aprovado pela Meta (documentos_pendentes) pelo caminho de modelo do hub (template_params
# na mensagem → Whatsapp::SendOnWhatsappService); a caixa sem esse modelo APROVADO (antes do número oficial) não manda nada.
# Textos e nome do modelo: config/ramon/documentos_cobranca.yml. Quem envia é o assistente da conversa (o da etapa Documentos).
module Ramon::Documentos::Envio
  CONFIG = Ramon::Documentos::Cobranca::CONFIG

  module_function

  # passo: :abertura, :lembrete_1 ou :lembrete_2. O checklist do lead tem de ter algo pendente (o CobrancaJob confere).
  # Texto do passo vazio ou nil no yml = passo desligado: nada sai, nem o modelo.
  # @return [Symbol] :texto, :modelo, :sem_permissao ou :desligado (nos dois últimos, nada enviado)
  def mandar(lead, passo)
    return :desligado if CONFIG.dig('mensagens', passo.to_s).blank?

    conversa = lead.conversation
    return :sem_permissao unless conversa

    if Conversations::MessageWindowService.new(conversa).can_reply?
      criar(conversa, texto(lead, passo))
      :texto
    elsif (modelo = modelo_aprovado(conversa))
      criar(conversa, corpo_do_modelo(lead), 'template_params' => template_params(lead, modelo))
      :modelo
    else
      :sem_permissao
    end
  end

  def criar(conversa, conteudo, extra = {})
    conversa.messages.create!(message_type: :outgoing, account_id: conversa.account_id, inbox_id: conversa.inbox_id, content: conteudo,
                              sender: Captain::AssistenteDaConversa.para(conversa), additional_attributes: extra)
  end

  def texto(lead, passo)
    pendentes = titulos(lead)
    lista = pendentes.map { |titulo| "- #{titulo}" }.join("\n")
    preencher(CONFIG.dig('mensagens', passo.to_s), '{nome}' => nome(lead), '{lista}' => lista, '{primeiro_item}' => pendentes.first.to_s)
  end

  def corpo_do_modelo(lead) = preencher(CONFIG.dig('modelo', 'corpo'), '{{1}}' => nome(lead), '{{2}}' => falta(lead))

  # Bloco, não string de troca: nome ou título com barra invertida não vira referência de grupo.
  def preencher(texto, valores) = texto.gsub(Regexp.union(valores.keys)) { |chave| valores[chave] }

  # O mesmo formato que a tela manda ao escolher um modelo (Whatsapp::TemplateProcessorService).
  def template_params(lead, modelo)
    { 'name' => modelo['name'], 'category' => modelo['category'], 'language' => modelo['language'],
      'processed_params' => { 'body' => { '1' => nome(lead), '2' => falta(lead) } } }
  end

  def modelo_aprovado(conversa)
    Array(conversa.inbox.channel.try(:message_templates)).find do |modelo|
      modelo['name'] == CONFIG.dig('modelo', 'nome') && modelo['status'].to_s.casecmp?('approved')
    end
  end

  def nome(lead) = lead.name.to_s.split.first.presence || 'cliente'

  # Variável do modelo: uma linha só (a Meta recusa quebra de linha em variável).
  def falta(lead) = titulos(lead).to_sentence(words_connector: ', ', two_words_connector: ' e ', last_word_connector: ' e ')

  def titulos(lead) = lead.docs_pendentes.pluck(:title)
end
