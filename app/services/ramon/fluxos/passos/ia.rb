# Passos de IA (spec §4.2/§4.3): perguntar_ia (condição sim/não), rascunho_ia (nota RASCUNHO
# escrita pela IA) e rodar_skill (skill de um assistente do Captain — só enterprise).
# LGPD: o que vai ao LLM passa pelo Pseudonymizer; [nome] volta como o primeiro nome.
# Lock: o Executor reivindica a execução numa transação curta e anda FORA de transação —
# IA lenta (até 90 s, Ramon::LlmClient::REQUEST_TIMEOUT) não segura lock; a trilha é gravada a cada passo.
module Ramon::Fluxos::Passos::Ia
  PROVIDER = 'deepseek'.freeze
  LIMITE_CONVERSA = 8_000 # caracteres do fim da conversa
  # chamadas de IA de fluxo por conta por dia (env RAMON_FLUXO_IA_DIA) — valor é decisão do Eduardo
  TETO_PADRAO = 200
  REGRAS = <<~TXT.freeze
    Regras obrigatórias (Provimento 205/2021 da OAB): nunca prometa resultado, prazo ou valor do INSS; não pressione nem ofereça vantagem;
    não cite valor de honorário diferente de 30% dos atrasados + 3 parcelas do benefício (o mesmo em todas as teses).
    Não invente fatos que não estejam no contexto. Para o nome do cliente escreva exatamente [nome].
  TXT
  SISTEMA_PERGUNTA = <<~TXT.freeze
    Você analisa um caso de um escritório de advocacia previdenciária e responde a uma pergunta de sim ou não.
    Responda APENAS JSON válido (sem markdown): {"resposta": "sim" ou "nao", "justificativa": "<uma frase>"}. Na dúvida, "nao".
    #{REGRAS}
  TXT
  SISTEMA_RASCUNHO = <<~TXT.freeze
    Você redige uma mensagem de WhatsApp que um atendente de um escritório de advocacia previdenciária vai revisar e enviar.
    Tom acolhedor, simples, sem juridiquês; 2 a 4 frases. Responda APENAS com o texto da mensagem, sem aspas nem assinatura.
    #{REGRAS}
  TXT

  module_function

  # Condição: roda de verdade inclusive no ensaio (spec §6).
  def perguntar_ia(config, ctx)
    cota!(ctx)
    pedido = "Pergunta: #{ctx.interpolar(config['pergunta'])}"
    json = JSON.parse(limpar(perguntar(SISTEMA_PERGUNTA, pedido, ctx)))
    sim = Ramon::Fluxos::Condicao.normal(json['resposta']).start_with?('sim')
    justificativa = restaurar(json['justificativa'].to_s, ctx)
    { saida: sim ? 'sim' : 'nao', vars: { 'resposta_ia' => justificativa },
      resumo: "IA: #{sim ? 'sim' : 'não'} — #{justificativa.truncate(100)}" }
  end

  # B4.3: onde/título como o rascunho de texto (a retomada vai para as notas do lead, "— retomada nº N:") e `reserva`:
  # se a IA falhar, entra esse texto fixo na hora (como a cadência do código) em vez de tentar de novo.
  def rascunho_ia(config, ctx)
    instrucao = ctx.interpolar(config['instrucao'])
    return { saida: 's', resumo: "faria: rascunho da IA (#{instrucao.truncate(80)})" } if ctx.ensaio?

    cota!(ctx)
    texto = texto_da_ia(instrucao, config, ctx)
    conversa = Ramon::Fluxos::Passos::Conversa
    conversa.escrever(ctx, "#{conversa.cabecalho(config, ctx)}\n#{texto}", onde: config['onde'])
    { saida: 's', vars: { 'resposta_ia' => texto }, resumo: "rascunho da IA: #{texto.truncate(120)}" }
  end

  # O cota! fica fora do rescue: teto de IA estourado continua falhando na hora, com sino.
  def texto_da_ia(instrucao, config, ctx)
    restaurar(perguntar(SISTEMA_RASCUNHO, "Instrução: #{instrucao}", ctx), ctx).strip
  rescue StandardError => e
    raise if config['reserva'].blank?

    Rails.logger.warn("[Ramon::Fluxos::Passos::Ia] rascunho_ia: IA falhou (#{e.class}) — texto de reserva")
    # {nome} passa pelo restaurar da resposta da IA: sem nome, "cliente" (como o código), nunca "Oi , tudo bem?"
    restaurar(ctx.interpolar(config['reserva'].gsub('{nome}', '[nome]')), ctx)
  end

  def rodar_skill(config, ctx)
    raise Ramon::Fluxos::PassoImpossivel, 'rodar skill precisa da edição enterprise (Captain)' unless ChatwootApp.enterprise?

    skill = Captain::Scenario.enabled.find_by(id: config['skill_id'], assistant_id: config['assistente_id'],
                                              account_id: ctx.execucao.account_id)
    raise Ramon::Fluxos::PassoImpossivel, 'skill não encontrada ou desligada' if skill.nil?
    return { saida: 's', resumo: "faria: skill \"#{skill.title}\" (#{skill.assistant.name})" } if ctx.ensaio?

    cota!(ctx)
    texto = restaurar(executar_skill(skill, config, ctx), ctx)
    Ramon::Fluxos::Passos::Conversa.escrever(ctx, "⚙ Skill #{skill.title}:\n#{texto}")
    { saida: 's', vars: { 'resposta_ia' => texto }, resumo: "skill #{skill.title}: #{texto.truncate(120)}" }
  end

  # Sem `conversation:` no runner (como o Testar): ferramentas que agem na conversa (handoff,
  # nota, prioridade) não acham a conversa e não fazem nada — nada chega ao cliente.
  def executar_skill(skill, config, ctx)
    pedido = "Use a skill \"#{skill.title}\". #{ctx.interpolar(config['instrucao'])}".strip
    mensagem = Ramon::Pseudonymizer.mask([pedido, dados_do_caso(ctx), transcricao(ctx)].compact_blank.join("\n\n"), names: nomes(ctx))
    resposta = Captain::Assistant::AgentRunnerService.new(assistant: skill.assistant, source: 'fluxo')
                                                     .generate_response(message_history: [{ role: 'user', content: mensagem }])
    raise "skill falhou: #{resposta['reasoning']}" if resposta['reasoning'].to_s.start_with?('Error occurred')

    resposta['response'].to_s
  end

  def perguntar(sistema, pedido, ctx)
    texto = [pedido, dados_do_caso(ctx), transcricao(ctx)].compact_blank.join("\n\n")
    Ramon::LlmClient.complete(provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'), system: sistema,
                              user: Ramon::Pseudonymizer.mask(texto, names: nomes(ctx))).content.to_s
  end

  def dados_do_caso(ctx)
    d = ctx.dados
    "Caso: tese #{d['tese'] || 'não informada'}; etapa #{d['etapa'] || '—'}; origem #{d['origem'] || '—'}; " \
      "documentos que faltam: #{d['documentos_faltantes'].presence || 'nenhum'}."
  end

  def transcricao(ctx)
    return if ctx.conversa.blank?

    "Conversa:\n#{LlmFormatter::ConversationLlmFormatter.new(ctx.conversa).format(token_limit: LIMITE_CONVERSA)}"
  end

  def nomes(ctx) = [ctx.lead&.name, ctx.lead&.contact&.name, ctx.conversa&.contact&.name].compact.uniq

  def restaurar(texto, ctx) = texto.gsub('[nome]', ctx.dados['nome'].presence || 'cliente')

  def limpar(conteudo) = conteudo.to_s.strip.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, '')

  # Teto por conta/dia (fuso SP) contado no Redis; estourou → falha na hora + sino de falha.
  def cota!(ctx)
    teto = ENV.fetch('RAMON_FLUXO_IA_DIA', TETO_PADRAO).to_i
    chave = "RAMON::FLUXO_IA::#{ctx.execucao.account_id}::#{Time.find_zone!(Fluxo::ZONA).today}"
    usadas = Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, 2.days.to_i) if usadas == 1
    raise Ramon::Fluxos::PassoImpossivel, "teto diário de IA dos fluxos atingido (#{teto})" if usadas > teto
  end
end
