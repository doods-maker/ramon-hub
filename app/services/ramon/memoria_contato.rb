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
  BENEFICIO = /aux[ií]lio[-\s]?(?:doen[cç]a|acidente)|aposentadoria\s+por\s+(?:incapacidade|invalidez)|\bBPC\b|\bLOAS\b/i
  # Espécie do INSS (B31, B91…). Algumas também são código CID (B91, B92…): perto de laudo/atestado/perícia, não sai.
  ESPECIE = /\bB\s?(?:31|32|36|41|42|46|87|88|91|92|93|94)\b/i
  DOC_MEDICO = /laudo|atestado|per[ií]cia/i
  # ponytail: lista de palavras — cobre o comum (doença, código CID tipo M54/F32, parte do corpo, condições do BPC); a
  # regra principal é o PROMPT. Se escapar algo, somar aqui. LER só em maiúsculas ("não sabe ler" não é saúde);
  # "operador" e "mão de obra" passam. "incapa…" pega incapacidade/incapaz; o nome do benefício
  # ("aposentadoria por incapacidade") já saiu antes, pelo BENEFICIO.
  # Borda da palavra por lookaround com \p{L} (e não \b + \w): no Ruby o \w é só ASCII e o \b é Unicode, então
  # "depress\w*\b" NÃO casaria "depressão". O lookbehind fica fora do /i (case fold de \p{L} no lookbehind pode não compilar).
  SAUDE = /(?-i:(?<![\p{L}\d]))(?:
            cid\d*|[a-z]\d{2}\.?\d?|diagn[oó]stic\p{L}*|doen[cç]a\p{L}*|doente\p{L}*|dor(?:es)?|les[aã]o|les[oõ]es|lesion\p{L}*|
            machuc\p{L}*|sequela\p{L}*|fratur\p{L}*|cirurgi\p{L}*|operad[oa]s?|internad\p{L}*|interna[cç][aã]o|rem[eé]di\p{L}*|
            medica\p{L}*|tratament\p{L}*|exame\p{L}*|depress\p{L}*|ansiedade|p[aâ]nico|s[ií]ndrome|transtorno|bipolar|
            esquizo\p{L}*|burnout|psiqui\p{L}*|psic[oó]\p{L}*|\p{L}*ologista|ortoped\p{L}*|fisioterapi\p{L}*|c[aâ]ncer|
            tumor\p{L}*|h[eé]rnia\p{L}*|tendinite|tend[aã]o|bursite|lombalgia|artros\p{L}*|artrit\p{L}*|fibromialg\p{L}*|
            ligamento\p{L}*|menisco|amput\p{L}*|defici[eê]n\p{L}*|autis\p{L}*|diabet\p{L}*|press[aã]o\s+alta|hipertens\p{L}*|
            hiv|aids|derrame|avc|infarto|epilep\p{L}*|hansen\p{L}*|gr[aá]vid\p{L}*|gesta[cçn]\p{L}*|(?-i:LER)|dort|
            olhos?|vis[aã]o|ceg(?:[oa]s?|ueira)|surd\p{L}*|auditiv\p{L}*|coluna|lombar|cervical|joelho\p{L}*|ombro\p{L}*|
            bra[cç]o\p{L}*|perna\p{L}*|m[aã]os?(?!\s+de\s+obra)|p[eé]s?|dedo\p{L}*|punho\p{L}*|quadril|tornozelo\p{L}*|
            costas|sa[uú]de|cora[cç][aã]o|card[ií]ac\p{L}*|cardiopat\p{L}*|pulm[aã]o|pulm[oõ]es|pulmonar\p{L}*|asma|asm[aá]tic\p{L}*|
            rim|rins|renal|renais|hemodi[aá]lise|di[aá]lise|covid\p{L}*|[aá]lcool\p{L}*|alco[oó]latra\p{L}*|depend[eê]ncia\s+qu[ií]mica|
            cadeirante\p{L}*|cadeira\s+de\s+rodas|acidente\s+vascular|incapa\p{L}*
          )(?![\p{L}\d])/ix
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

  def saude?(item)
    limpo = item.gsub(BENEFICIO, '')
    limpo = limpo.gsub(ESPECIE, '') unless item.match?(DOC_MEDICO)
    limpo.match?(SAUDE)
  end

  # Uma nota no lead (sem autor: foi a IA). Nada a gravar (vazio, ou só item de saúde) → nil.
  def gravar!(lead, numero_conversa, itens)
    limpos = itens.map(&:strip).compact_blank.reject { |item| saude?(item) }.first(MAX_ITENS)
    return if limpos.empty?

    corpo = "#{CABECALHO} (conversa ##{numero_conversa}):\n#{limpos.map { |item| "- #{item}" }.join("\n")}"
    lead.lead_notes.create!(account: lead.account, body: corpo.truncate(1000))
  end
end
