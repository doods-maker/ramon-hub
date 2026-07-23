class Ramon::ConversationCopilotService
  class EmptyConversationError < StandardError; end

  MODES = %w[summary draft].freeze
  MAX_MESSAGES = 200
  PROVIDER = 'deepseek'.freeze

  SUMMARY_SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o copiloto comercial de um escritório de advocacia previdenciária no Brasil.
    Receberá a transcrição de uma conversa de WhatsApp/chat entre o atendimento e um lead.
    Produza um resumo estruturado, em português do Brasil, exatamente nestas seções (markdown simples):

    **Situação do lead** — quem é, o que aconteceu, em 2-4 linhas.
    **Tese provável** — qual benefício/tese previdenciária parece se aplicar e por quê.
    **Pendências** — o que falta perguntar, confirmar ou receber (documentos, datas, respostas).
    **Próximo passo** — a ação concreta mais importante agora.
    **Perfil de comunicação** — qual dos 4 perfis o cliente aparenta (intuitivo, pessoal, funcional ou analítico) e como agir com ele, em 1 linha.

    Seja fiel à conversa; não invente fatos. Se algo não apareceu na conversa, diga "não informado".
    Dados pessoais aparecem mascarados como [nome], [cpf], [telefone] — mantenha os marcadores como estão.
  PROMPT

  DRAFT_SYSTEM_PROMPT = <<~PROMPT.freeze
    Você redige uma sugestão de resposta para o atendente de um escritório de advocacia previdenciária
    enviar no WhatsApp do cliente. Tom de "médico de confiança": caloroso, acolhedor, simples, sem juridiquês.
    Regras obrigatórias:
    - Curto, estilo WhatsApp: 2 a 5 frases.
    - NUNCA prometa resultado do caso nem prazo do INSS (regra da OAB).
    - Não invente fatos que não estejam na conversa.
    - Se precisar chamar o cliente pelo nome, escreva exatamente [nome].
    - Detecte o perfil de comunicação do cliente e adapte o tom: intuitivo (quer resultado) → direto ao ponto;
      pessoal (busca vínculo) → mais afeto e acolhimento; funcional (quer o passo a passo) → caminho em etapas simples;
      analítico (quer detalhe e prova) → traga o fundamento com clareza.
    - Se a última mensagem do cliente contém uma objeção, contorne em 4 passos na própria resposta:
      concorde com a preocupação → amenize com empatia ou prova social → contorne com segurança → avance com um próximo passo.
    - Use no máximo 1 gatilho mental adequado por mensagem — nunca empilhe gatilhos.
    Responda APENAS com o texto da mensagem, sem aspas, sem comentários e sem assinatura.
  PROMPT

  def initialize(conversation, mode)
    @conversation = conversation
    @mode = mode.to_s
    @lead = conversation.account.leads.find_by(conversation_id: conversation.id)
  end

  # Síncrono de propósito (mesmo desenho do "AI assist" upstream): o resultado é
  # efêmero — vai pro painel ou pro editor — então não há o que persistir/pollar.
  def perform
    result = Ramon::LlmClient.complete(provider: PROVIDER,
                                       model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
                                       system: system_prompt, user: user_prompt)
    restore_name(result.content)
  end

  private

  def system_prompt
    @mode == 'draft' ? DRAFT_SYSTEM_PROMPT : SUMMARY_SYSTEM_PROMPT
  end

  # Pseudonimizado (LGPD, padrão do PR #33): o texto só sai daqui mascarado.
  def user_prompt
    text = [lead_sheet, transcript].compact_blank.join("\n\n")
    Ramon::Pseudonymizer.mask(text, names: [@lead&.name, @conversation.contact&.name])
  end

  def lead_sheet
    return nil if @lead.blank?

    parts = ["Lead: #{@lead.name}"]
    parts << "Etapa no funil: #{@lead.lead_stage.name}" if @lead.lead_stage
    parts << "Benefício de interesse: #{@lead.benefit_type.name}" if @lead.benefit_type
    parts << "Tese: #{@lead.thesis.name}" if @lead.thesis
    parts.join("\n")
  end

  # ponytail: transcript espelha Leads::TriageService#conversation_transcript;
  # extrair helper comum se surgir um 3º consumidor.
  def transcript
    messages = @conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                            .order(:created_at).last(MAX_MESSAGES)
    lines = messages.filter_map do |m|
      text = m.content_for_llm
      next if text.blank? || text == '[Attachment]'

      "#{m.incoming? ? 'Cliente' : 'Atendimento'}: #{text}"
    end
    raise EmptyConversationError, 'Conversa sem mensagens de texto para analisar' if lines.empty?

    "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end

  # O Pseudonymizer não guarda mapa reverso; o único marcador que interessa
  # devolver é [nome] — trocamos pelo primeiro nome, que nunca saiu do servidor.
  def restore_name(content)
    first_name = (@lead&.name.presence || @conversation.contact&.name).to_s.split.first
    return content if first_name.blank?

    content.gsub('[nome]', first_name)
  end
end
