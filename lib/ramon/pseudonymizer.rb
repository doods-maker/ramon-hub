class Ramon::Pseudonymizer
  # Pseudonimização LGPD: mascara identificadores diretos antes do texto ir
  # pra um LLM externo. Valores em R$ e datas ficam intactos de propósito —
  # importam pra análise de viabilidade.
  EMAIL = /\b[\w+.-]+@[\w-]+\.[\w.-]+\b/
  CEP = /\b\d{5}-\d{3}\b/
  CPF = /\b\d{3}\.\d{3}\.\d{3}-?\d{2}\b|\b\d{11}\b/
  # Formatos BR (ex.: "(48) 99999-8888", "48 99999 8888", "999998888");
  # dinheiro e datas não casam (usam , . / e grupos curtos de dígitos).
  PHONE = /(?:\+?55[\s.-]?)?(?:\(\d{2}\)[\s.-]?|\b\d{2}[\s.-])?9?\d{4,5}[\s.-]?\d{4}\b/
  # ponytail: só mascara endereço com número ("Rua X, 123") — sem número o nome
  # da rua passa, pra não engolir frases comuns tipo "caí na rua e machuquei".
  ADDRESS = /\b(?:rua|avenida|av\.|travessa|rodovia|estrada|alameda|servid[ãa]o)\s+[^\n,;.]{3,40},?\s*(?:n[ºo°.]?\s*)?\d+\b/i
  # RG dito na reunião (o prompt da colheita pede RG explicitamente): número
  # logo depois da palavra "RG" ou no formato pontuado clássico. Roda DEPOIS
  # do CPF (que consome os 11 dígitos/pontuado próprio); lookahead evita comer
  # a casa de milhão de um valor em R$. ponytail: RG solto sem rótulo nem
  # pontuação não casa — indistinguível de número comum.
  RG_LABELED = /\bRG\b[^\d\n]{0,8}\d[\d.\s-]{4,12}\d/i
  RG_PUNCT = /\b\d{1,2}\.\d{3}\.\d{3}(?:-?\d)?\b(?!,\d)/
  NAME_STOPWORDS = %w[dos das de da do e].freeze
  # Senha (gov.br e afins) nunca vai a LLM, nem no caminho sem pseudonimização
  # (Message#content_for_llm chama sem_senha). Na linha que fala em "senha", só a
  # palavra com cara de senha vira [senha] ("esqueci a senha do gov.br" fica
  # legível para a IA que atende); se a linha termina esperando o valor
  # ("Senha:"), a próxima linha não vazia some inteira.
  # ponytail: senha só de letras ("cachorro") na mesma linha passa, e senha fora de
  # linha com "senha" também; a mandada sozinha logo depois do pedido é pega em
  # Message#senha_solta?. Upgrade: detector de entropia.
  SENHA = /senha/i
  SENHA_MASCARA = '[senha]'.freeze
  SENHA_ESPERA_VALOR = /[:=-]\s*\z/
  # Palavra de 6+ caracteres com número ou símbolo ("Tx9#kLm2"); "kkkkkk" e "obrigadão" não.
  SENHA_FORMATO = /\A(?=\S*[^[:alpha:]\s])\S{6,}\z/
  SENHA_NAO_E = /senha|gov\.br|inss|https?:|www\./i

  def self.senha_provavel?(palavra)
    palavra.match?(SENHA_FORMATO) && !palavra.match?(SENHA_NAO_E)
  end

  def self.sem_senha(text)
    proxima = false
    text.to_s.split("\n", -1).map do |linha|
      if proxima
        next linha if linha.strip.empty?

        proxima = false
        next SENHA_MASCARA
      end

      i = linha.index(SENHA)
      next linha if i.nil?

      proxima = linha.match?(SENHA_ESPERA_VALOR)
      linha[0, i] + linha[i..].gsub(/\S+/) { |palavra| senha_provavel?(palavra) ? SENHA_MASCARA : palavra }
    end.join("\n")
  end

  def self.mask(text, names: [])
    masked = sem_senha(text)
    name_tokens(names).each { |token| masked.gsub!(/\b#{Regexp.escape(token)}\b/i, '[nome]') }
    masked.gsub!(EMAIL, '[email]')
    masked.gsub!(CEP, '[cep]')
    masked.gsub!(CPF, '[cpf]')
    masked.gsub!(RG_LABELED, '[rg]')
    masked.gsub!(RG_PUNCT, '[rg]')
    masked.gsub!(PHONE, '[telefone]')
    masked.gsub!(ADDRESS, '[endereco]')
    masked
  end

  # Nome completo + cada parte (menos conectivos), maior primeiro,
  # pra pegar "Maria das Dores" e também um "Maria" solto na conversa.
  def self.name_tokens(names)
    names.compact_blank.flat_map { |name| [name.strip] + name.split }
         .uniq.reject { |t| t.length < 3 || NAME_STOPWORDS.include?(t.downcase) }
         .sort_by { |t| -t.length }
  end
end
