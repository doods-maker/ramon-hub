# Avalia a saída de um caso de teste da IA: primeiro as regras fixas (baratas,
# determinísticas); só se todas passarem e houver rubrica, chama o juiz — um
# LLM barato (modelo do copiloto) que devolve {passou, motivo}.
#
# saida = { resposta:, ferramentas: [{ nome:, resultado: }], handoff: }
class Captain::IaAvaliadorService
  PROVIDER = 'deepseek'.freeze
  JUIZ = <<~PROMPT.freeze
    Você é o avaliador dos casos de teste da IA de atendimento de um escritório de advocacia previdenciária.
    Recebe a conversa, a resposta da IA, as ferramentas que ela pediu (em teste nada é executado: "[TESTE] faria X")
    e se passou para um humano. Julgue SÓ pelo critério dado — não invente exigências.
    Marcas do critério: [FAQ] consultou a FAQ · [PB] playbook da tese · [HUM] passou para humano ·
    [SUG] pediu ação que vira sugestão pendente (nada executa) · [NUNCA] frase proibida.
    Responda APENAS com JSON: {"passou": true|false, "motivo": "uma frase curta em português"}.
  PROMPT

  def initialize(caso, saida)
    @caso = caso
    @criterios = caso.criterios
    @saida = saida
  end

  def avaliar
    motivos = regras_fixas
    motivos << juiz if motivos.empty? && @criterios['rubrica'].present?
    motivos.compact!
    { passou: motivos.empty?, motivos: motivos }
  end

  private

  def regras_fixas
    regras_ferramentas + regra_handoff + regras_texto
  end

  def regras_ferramentas
    usadas = @saida[:ferramentas].pluck(:nome)
    (lista('deve_usar') - usadas).map { |id| "Não usou #{id}" } +
      (lista('nao_deve_usar') & usadas).map { |id| "Usou #{id}, que não devia" }
  end

  def regras_texto
    lista('deve_conter').reject { |padrao| contem?(padrao) }.map { |padrao| "Faltou: #{padrao}" } +
      lista('nao_pode_conter').select { |padrao| contem?(padrao) }.map { |padrao| "Disse o proibido: #{padrao}" }
  end

  def lista(chave)
    Array(@criterios[chave])
  end

  def regra_handoff
    esperado = @criterios['handoff']
    return ['Não passou para humano'] if esperado == 'sim' && !@saida[:handoff]
    return ['Passou para humano sem precisar'] if esperado == 'nao' && @saida[:handoff]

    []
  end

  # "/regex/" = expressão regular sem caixa; o resto = frase, sem acento nem caixa.
  def contem?(padrao)
    if padrao.length > 2 && padrao.start_with?('/') && padrao.end_with?('/')
      Regexp.new(padrao[1..-2], Regexp::IGNORECASE, timeout: 1).match?(@saida[:resposta])
    else
      normalizar(@saida[:resposta]).include?(normalizar(padrao))
    end
  rescue RegexpError, Regexp::TimeoutError
    false
  end

  def normalizar(texto)
    I18n.transliterate(texto.to_s).downcase.squish
  end

  def juiz
    resultado = Ramon::LlmClient.complete(provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
                                          system: JUIZ, user: pergunta_ao_juiz, sensitive: true)
    veredito = JSON.parse(resultado.content.to_s[/\{.*\}/m].to_s)
    veredito['passou'] == true ? nil : "Juiz: #{veredito['motivo'].presence || 'reprovou'}"
  rescue StandardError => e
    "Juiz indisponível (#{e.class.name})"
  end

  def pergunta_ao_juiz
    conversa = @caso.message_history.map { |fala| "#{fala[:role] == 'user' ? 'Pessoa' : 'IA'}: #{fala[:content]}" }.join("\n")
    ferramentas = @saida[:ferramentas].map { |tool| "- #{tool[:nome]}: #{tool[:resultado].to_s.truncate(200)}" }.join("\n").presence || '(nenhuma)'
    <<~TEXTO
      CONVERSA:
      #{conversa}

      RESPOSTA DA IA:
      #{@saida[:resposta]}

      FERRAMENTAS PEDIDAS:
      #{ferramentas}

      PASSOU PARA HUMANO: #{@saida[:handoff] ? 'sim' : 'não'}

      CRITÉRIO:
      #{@criterios['rubrica']}
    TEXTO
  end
end
