# Extração estruturada da colheita (artefato 2 da colheita aprovada em
# 15/07/2026) a partir do transcript da conversa — roda após cada transcrição
# de áudio do Whisper e, com debounce, após mensagens de chat do lead.
# Preenche lead.custom_attributes['colheita'] (dados + lacunas), marca 'ia'
# nos itens do checklist já respondidos (colheita_status, sem sobrescrever
# escolha humana), CPF/nascimento vazios do contato (cadastro) e dcb_em
# quando ainda vazio (relógio de prescrição).
class Ramon::ColheitaExtractionService
  MAX_MESSAGES = 200
  AUXILIO_DOENCA = %w[B31 B91].freeze

  PROMPT_ABERTURA = <<~PROMPT.freeze
    Você extrai dados estruturados da conversa entre a equipe de um escritório previdenciário e um cliente com possível caso de %<tese>s.
    Responda APENAS com um objeto JSON válido (sem texto fora do JSON, sem cercas de código), nesta forma exata:
  PROMPT

  PROMPT_REGRAS = <<~PROMPT.freeze
    Regras invioláveis:
    - NUNCA invente um dado. Campo não mencionado na conversa = null (ou lista vazia) + entrada em "lacunas".
    - Datas no formato YYYY-MM-DD; se só mês/ano foi dito, use o dia 15 e liste o campo em "confirmar". Valor com "|" no modelo ("a|b|c") = escolha UMA das opções; lista com um item assim (["a|b|c"]) = lista cujos itens são cada um uma dessas opções.
    - Valor dito de forma incerta na fala: preencha e liste o caminho do campo em "confirmar".
    - Tokens de máscara ([cpf], [rg], [telefone], [endereco], [email], [cep], [nome]) significam dado protegido: deixe o campo null e registre em "lacunas" com como_obter "confirmar no cadastro/documento".
    - "profissao" é a atividade habitual; "sequela.limitacao_concreta" é como a sequela reduz esse trabalho, em fatos.
    - "cliente" é a pessoa titular do benefício; se quem conversa é outra pessoa (familiar, curador), ela vai em "cliente.representante".
    - "cliente.representante" e "outras_teses_sinal" ficam vazios (null / lista vazia) quando não se aplicam, sem entrada em "lacunas".
    - "outras_teses_sinal": só preencha quando a conversa der motivo concreto para outra tese.
    - A IA não calcula nada (renda per capita, prazos, carência, somas): só registra o que foi dito.
    - Caminhos em "confirmar" e "lacunas": "bloco.campo"; listas com índice, ex.: "saude.doencas[0].cid".
    - "dependencia.quem_cuida": só o parentesco, sem nome.
    - "ir.valor_mensal" sem valor dito: 5001 se a renda passou de R$ 5.000, 5000 se não; nesse caso liste ir.valor_mensal em confirmar.
    - "segurado" refere-se à data em que parou de contribuir (B31/B32) ou ao parto (maternidade).
    - "vinculo.avaliacao": uma linha por requisito.
    - Testemunhas: só com o que o lead disse na conversa; nunca sugira nomes.
    - "checklist_ok": ids (números) dos itens do checklist listados na entrada que a conversa JÁ responde com clareza; na dúvida, NÃO inclua o item.
    - "fontes": para cada campo preenchido, a data dd/mm da mensagem de onde ele saiu (o carimbo da linha), no formato {"bloco.campo": "dd/mm"}.
    - "trechos": no máximo 3, literais e curtos (até 300 caracteres), só onde o relato decide — como o acidente/doença aconteceu, a limitação concreta, a queixa principal.
    Português do Brasil.
  PROMPT

  def initialize(lead)
    @lead = lead
  end

  def perform
    return unless extractable?

    transcript = conversation_transcript
    return if transcript.blank?

    result = call_llm(transcript)
    write_back(parse(result.content))
  rescue Ramon::LlmClient::TransientError
    raise
  rescue StandardError => e
    Rails.logger.error("ColheitaExtraction: falha no lead #{@lead.id}: #{e.message}")
  end

  def extractable?
    @lead.thesis.present? && @lead.conversation.present?
  end

  private

  def provider
    ENV.fetch('RAMON_COLHEITA_PROVIDER', 'anthropic')
  end

  def model
    ENV.fetch('RAMON_COLHEITA_MODEL', Ramon::LlmEscolha::MODELO_INTERNO)
  end

  # Com provider autorizado p/ dado sensível (lista configurável no LlmClient)
  # o transcript vai íntegro e a extração cobre identificação civil; senão vai
  # pseudonimizado (LGPD) — PII mascarada vira lacuna, datas/valores extraem normal.
  def sensitive_ok?
    Ramon::LlmClient.sensitive_ok_providers.include?(provider)
  end

  def system_prompt
    nome = @lead.thesis.name
    "#{format(PROMPT_ABERTURA, tese: nome)}#{Ramon::Colheita::Esquema.modelo_json(nome)}
#{PROMPT_REGRAS}"
  end

  def call_llm(transcript)
    text = "Tese: #{@lead.thesis.name}\n\n#{checklist_block}#{transcript}"
    text = Ramon::Pseudonymizer.mask(text, names: [@lead.name, @lead.contact&.name]) unless sensitive_ok?
    Ramon::LlmClient.complete(provider: provider, model: model, system: system_prompt, user: text, sensitive: sensitive_ok?,
                              funcao: 'colheita', account_id: @lead.account_id, lead_id: @lead.id)
  end

  def checklist_items
    @checklist_items ||= @lead.thesis.thesis_items.where(section: 'colheita')
  end

  def checklist_block
    return '' if checklist_items.empty?

    lines = checklist_items.map { |item| "#{item.id}: #{item.title.presence || item.content}" }
    "Itens do checklist da colheita (id: item):\n#{lines.join("\n")}\n\n"
  end

  def conversation_transcript
    Ramon::Transcricao.de(@lead.conversation, limite: MAX_MESSAGES, com_hora: true)
  end

  # Mesmo parse tolerante do Leads::KitService: aceita cercas ```json e texto em volta.
  def parse(raw)
    body = raw.to_s.gsub(/```json/i, '').gsub('```', '')
    ini = body.index('{')
    fim = body.rindex('}')
    raise ArgumentError, 'Resposta da IA não contém JSON da colheita.' if ini.nil? || fim.nil? || fim <= ini

    obj = JSON.parse(body[ini..fim])
    raise ArgumentError, 'Colheita sem objeto raiz.' unless obj.is_a?(Hash)

    # JSON válido mas fora do schema (LLM divagou) não pode sobrescrever colheita boa.
    blocos = Ramon::Colheita::Esquema.blocos_para(@lead.thesis.name) - %w[fechamento]
    raise ArgumentError, 'JSON fora do schema da colheita.' unless obj.keys.intersect?(blocos)

    obj
  rescue JSON::ParserError
    raise ArgumentError, 'JSON da colheita inválido.'
  end

  # A chamada de LLM demora — reload antes do merge, senão o snapshot velho
  # reverte o que painel/ZapSign/AdvBox gravaram nesse meio-tempo (e o guard
  # do dcb_em avaliaria dado obsoleto, sobrescrevendo valor humano).
  def write_back(dados)
    @lead.reload
    dados = dados.slice(*Ramon::Colheita::Esquema.blocos_para(@lead.thesis.name), 'lacunas', 'confirmar', 'checklist_ok', 'fontes', 'trechos')
    fill_contact_blanks(dados['cliente'])
    attrs = { custom_attributes: merged_custom_attributes(dados) }
    dcb = extracted_dcb(dados)
    attrs[:dcb_em] = dcb if dcb && @lead.dcb_em.blank?
    @lead.update!(attrs)
  end

  # Cadastro: CPF e nascimento têm coluna própria no contato (Linha da Vida,
  # ZapSign) — a extração preenche SÓ campo vazio; dado humano nunca é tocado.
  # Roda antes do update! do lead pro broadcast já sair com o contato novo.
  def fill_contact_blanks(cliente)
    contact = @lead.contact
    return if contact.blank? || !cliente.is_a?(Hash)
    # Com representante, quem conversa não é o autor: CPF/nascimento da colheita são do beneficiário.
    return if cliente.dig('representante', 'nome').present?

    updates = contact_updates(contact, cliente)
    return if updates.empty?
    return if contact.update(updates)

    # CPF inválido/duplicado não pode derrubar a colheita: tenta sem ele.
    updates.delete(:cpf)
    contact.reload.update(updates) if updates.any?
  end

  def contact_updates(contact, cliente)
    updates = {}
    cpf = cliente['cpf'].to_s.gsub(/\D/, '')
    updates[:cpf] = cpf if contact.cpf.blank? && cpf.present?
    nascimento = parse_date(cliente['nascimento'])
    updates[:data_nascimento] = nascimento if contact.data_nascimento.blank? && nascimento
    updates
  end

  def merged_custom_attributes(dados)
    merged = (@lead.custom_attributes || {}).merge('colheita' => colheita_payload(dados))
    status = checklist_status_with_ai(dados, merged['colheita_status'] || {})
    merged['colheita_status'] = status if status
    merged
  end

  # Itens do checklist que a conversa já responde ganham 'ia' — mas SÓ em chave
  # que o humano nunca tocou: true (marcou) e false (desmarcou = veto) são dele.
  def checklist_status_with_ai(dados, current)
    valid_ids = checklist_items.map { |item| item.id.to_s }
    additions = (Array(dados['checklist_ok']).map(&:to_s) & valid_ids).reject { |id| current.key?(id) }
    return nil if additions.empty?

    current.merge(additions.index_with { 'ia' })
  end

  def colheita_payload(dados)
    {
      'dados' => dados.except('lacunas', 'confirmar', 'checklist_ok', 'fontes', 'trechos'),
      'lacunas' => lacuna_list(dados['lacunas']),
      'confirmar' => Array(dados['confirmar']).map(&:to_s).reject(&:empty?),
      'fontes' => fonte_map(dados['fontes']),
      'trechos' => trecho_list(dados['trechos']),
      'extraida_em' => Time.zone.now.iso8601,
      'mascarada' => !sensitive_ok?
    }
  end

  def fonte_map(value)
    return {} unless value.is_a?(Hash)

    value.select { |campo, data| campo.is_a?(String) && data.is_a?(String) }
  end

  def trecho_list(value)
    Array(value).filter_map do |item|
      next unless item.is_a?(Hash) && item['texto'].present?

      { 'campo' => item['campo'].to_s, 'texto' => item['texto'].to_s.truncate(300) }
    end.first(3)
  end

  def lacuna_list(value)
    Array(value).filter_map do |item|
      next unless item.is_a?(Hash)

      campo = item['campo'].to_s
      campo.empty? ? nil : { 'campo' => campo, 'como_obter' => item['como_obter'].to_s }
    end
  end

  # DCB do auxílio-doença cessado mais recente = termo inicial do auxílio-acidente
  # (Tema 862/STJ) → alimenta o relógio de prescrição (só no B36). Nunca sobrescreve dado humano.
  def extracted_dcb(dados)
    return unless Ramon::Colheita::Esquema.tese(@lead.thesis.name) == :b36

    Array(dados['beneficios']).filter_map do |b|
      next unless b.is_a?(Hash)
      next unless AUXILIO_DOENCA.include?(b['especie'].to_s.upcase)
      next unless b['situacao'].to_s == 'cessado'

      parse_date(b['dcb'])
    end.max
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
