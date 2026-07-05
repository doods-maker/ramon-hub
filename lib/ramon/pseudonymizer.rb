class Ramon::Pseudonymizer
  # Pseudonimização LGPD: mascara identificadores diretos antes do texto ir
  # pra um LLM externo. Valores em R$ e datas ficam intactos de propósito —
  # importam pra análise de viabilidade.
  EMAIL = /\b[\w+.-]+@[\w-]+\.[\w.-]+\b/
  CEP = /\b\d{5}-\d{3}\b/
  CPF = /\b\d{3}\.\d{3}\.\d{3}-?\d{2}\b|\b\d{11}\b/
  # Formatos BR (ex.: "(48) 99999-8888", "48 99999 8888", "999998888");
  # dinheiro e datas não casam (usam , . / e grupos curtos de dígitos).
  PHONE = /(?:\+?55[\s.-]?)?(?:\(\d{2}\)[\s.-]?|\b\d{2}[\s.-])?9?\s?\d{4,5}[\s.-]?\d{4}\b/
  # ponytail: só mascara endereço com número ("Rua X, 123") — sem número o nome
  # da rua passa, pra não engolir frases comuns tipo "caí na rua e machuquei".
  ADDRESS = /\b(?:rua|avenida|av\.|travessa|rodovia|estrada|alameda|servid[ãa]o)\s+[^\n,;.]{3,40},?\s*(?:n[ºo°.]?\s*)?\d+\b/i
  NAME_STOPWORDS = %w[dos das de da do e].freeze

  def self.mask(text, names: [])
    masked = text.to_s.dup
    name_tokens(names).each { |token| masked.gsub!(/\b#{Regexp.escape(token)}\b/i, '[nome]') }
    masked.gsub!(EMAIL, '[email]')
    masked.gsub!(CEP, '[cep]')
    masked.gsub!(CPF, '[cpf]')
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
