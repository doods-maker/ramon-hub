# Memória do contato (Inteligência A5 — I-X7): ao resolver uma conversa numa caixa do assistente com a chave
# "Memória do contato" ligada, a IA lê o fim da conversa (mascarado, sem notas privadas — Ramon::FaqDeConversa.texto)
# e grava UMA nota no lead (painel → Notas) com o que aprendeu. As peças sem Captain ficam aqui (o CI testa); a
# chamada ao LLM fica no Captain::Llm::ContactNotesService (enterprise).
# O que pode ser anotado: PROMPT (decisão N1 do Eduardo — sem dado de saúde). SAUDE é a rede de segurança: item que
# bate nela não é gravado nem se a IA escrever.
module Ramon::MemoriaContato
  CABECALHO = 'MEMÓRIA DA IA'.freeze
  MAX_ITENS = 6
  ANTERIORES = 3
  # Nome/espécie de benefício não é dado de saúde: sai do item antes do teste (senão "auxílio-doença" cairia por "doença").
  BENEFICIO = /aux[ií]lio[-\s]?(?:doen[cç]a|acidente)|aposentadoria\s+por\s+(?:incapacidade|invalidez)|\bBPC\b|\bLOAS\b|
               \bB\s?(?:31|32|36|41|42|46|87|88|91|92|93|94)\b/ix
  # ponytail: lista de palavras — cobre o comum (doença, código CID tipo M54/F32, parte do corpo); a regra principal é o
  # PROMPT. Se escapar algo, somar aqui. LER só em maiúsculas ("não sabe ler" não é saúde).
  # Borda da palavra por lookaround com \p{L} (e não \b + \w): no Ruby o \w é só ASCII e o \b é Unicode, então
  # "depress\w*\b" NÃO casaria "depressão".
  SAUDE = /(?<![\p{L}\d])(?:cid|[a-z]\d{2}\.?\d?|diagn[oó]stic\p{L}*|doen[cç]a\p{L}*|les[aã]o|les[oõ]es|sequela\p{L}*|
            fratur\p{L}*|cirurgi\p{L}*|rem[eé]di\p{L}*|medica\p{L}*|tratament\p{L}*|exame\p{L}*|depress\p{L}*|ansiedade|
            c[aâ]ncer|tumor\p{L}*|h[eé]rnia\p{L}*|tendinite|bursite|lombalgia|amputa\p{L}*|psiqui\p{L}*|fisioterapi\p{L}*|
            (?-i:LER)|dort|avc|infarto|coluna|lombar|cervical|joelho\p{L}*|ombro\p{L}*|bra[cç]o\p{L}*|perna\p{L}*|
            dedo\p{L}*|punho\p{L}*|quadril|tornozelo\p{L}*|costas|sa[uú]de)(?![\p{L}\d])/ix
  PROMPT = <<~TXT.freeze
    Você lê o fim de uma conversa de WhatsApp entre um escritório de advocacia previdenciária e trabalhista
    (Support Agent) e um lead (User) e anota, para a equipe, o que vale lembrar sobre ESTA pessoa na próxima conversa.
    Responda APENAS JSON válido, sem markdown: {"memoria": ["...", "..."]}.
    Anote só fatos que a pessoa disse ou confirmou, um por item, curtos (até 15 palavras):
    - benefício ou assunto de interesse (ex.: auxílio-acidente, BPC, aposentadoria, trabalhista);
    - situação de trabalho (trabalhando, afastado, desempregado), profissão e ramo do empregador;
    - quando aconteceu o fato principal (mês/ano do acidente, do afastamento, da demissão);
    - benefício do INSS que já recebeu ou recebe (espécie e período) e se teve pedido negado;
    - documentos que já tem ou disse que vai mandar; se tem laudo ou atestado (só sim ou não);
    - melhor horário ou canal para falar; dúvidas e objeções que levantou (preço, prazo, desconfiança).
    NUNCA anote: doença, diagnóstico, CID, lesão, parte do corpo, remédio, exame, tratamento ou qualquer detalhe de
    saúde; CPF, RG, telefone, e-mail ou endereço; nome ou dados de outras pessoas (familiares, colegas).
    Não repita o que está em "Já anotado antes". Não invente; na dúvida, deixe de fora.
    No máximo 6 itens. Se não houver nada novo, responda {"memoria": []}.
    Escreva em português do Brasil.
  TXT

  module_function

  # O que vai ao LLM: as últimas memórias do lead (para não repetir) + o fim da conversa, tudo mascarado.
  def texto(conversa, lead)
    ja_sabe = lead.lead_notes.where('body LIKE ?', "#{CABECALHO}%").reorder(id: :desc).limit(ANTERIORES).pluck(:body).reverse
    conversa_txt = "Conversa:\n#{Ramon::FaqDeConversa.texto(conversa)}"
    return conversa_txt if ja_sabe.empty?

    anteriores = Ramon::Pseudonymizer.mask(ja_sabe.join("\n"), names: Ramon::FaqDeConversa.nomes(conversa))
    "Já anotado antes:\n#{anteriores}\n\n#{conversa_txt}"
  end

  # {"memoria": [...]} da resposta da IA; qualquer outra coisa vira lista vazia.
  def itens(conteudo)
    dados = JSON.parse(conteudo.to_s[/\{.*\}/m] || '{}')
    Array(dados['memoria']).map(&:to_s)
  rescue JSON::ParserError
    []
  end

  def saude?(item) = item.gsub(BENEFICIO, '').match?(SAUDE)

  # Uma nota no lead (sem autor: foi a IA). Nada a gravar (vazio, ou só item de saúde) → nil.
  def gravar!(lead, numero_conversa, itens)
    limpos = itens.map(&:strip).compact_blank.reject { |item| saude?(item) }.first(MAX_ITENS)
    return if limpos.empty?

    corpo = "#{CABECALHO} (conversa ##{numero_conversa}):\n#{limpos.map { |item| "- #{item}" }.join("\n")}"
    lead.lead_notes.create!(account: lead.account, body: corpo.truncate(1000))
  end
end
