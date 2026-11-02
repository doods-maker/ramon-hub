# Decide, a partir da listagem de uma pasta do Drive, a ordem do pacote e as recusas. Puro: não toca em Drive nem banco.
module Ramon::Peticionamento::RegrasDaPasta
  Resultado = Data.define(:arquivos, :recusas, :avisos)

  PDF = 'application/pdf'.freeze
  IMAGENS = %w[image/jpeg image/png].freeze
  DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'.freeze
  NUMERO = /\A(\d+)(?:\.(\d+))?[\s._-]*/

  def self.call(itens)
    subpastas, validos, words, estranhos = classificar(itens)
    recusas = estranhos.map { |i| "formato:#{i[:name]}" }
    arquivos = ordenar(validos, recusas)
    words_sem_pdf(words, arquivos, recusas)
    recusas.unshift('sem_pdf') unless arquivos.first&.fetch(:mime_type) == PDF # peça principal não pode ser imagem

    Resultado.new(arquivos: arquivos.map { |a| a.slice(:id, :name, :mime_type, :nome_limpo) }, recusas: recusas,
                  avisos: subpastas.any? ? ["subpastas:#{subpastas.pluck(:name).join(', ')}"] : [])
  end

  def self.classificar(itens)
    itens = itens.reject { |i| i[:name].to_s.start_with?('_') } # _pasta-pronta.json etc.: ignorados sem aviso
    subpastas, itens = itens.partition { |i| i[:pasta] }
    validos, resto = itens.partition { |i| [PDF, *IMAGENS].include?(i[:mime_type]) }
    words, estranhos = resto.partition { |i| i[:mime_type] == DOCX } # Google Docs nativo cai em estranhos (formato:)
    [subpastas, validos, words, estranhos]
  end

  def self.chave(nome)
    m = NUMERO.match(nome.to_s)
    m && [m[1].to_i, m[2].to_i]
  end

  # Sem número ou número repetido → recusa; o resto sai ordenado por [maior, menor].
  def self.ordenar(validos, recusas)
    vistos = {}
    ok = validos.filter_map do |i|
      k = chave(i[:name])
      if k.nil? then recusas << "sem_numero:#{i[:name]}"
      elsif vistos[k] then recusas << "numero_repetido:#{i[:name]}"
      else
        vistos[k] = true
        i.merge(chave: k, nome_limpo: i[:name].sub(NUMERO, ''))
      end
    end
    ok.sort_by { |i| i[:chave] }
  end

  # Word só é ignorado quando já existe PDF/imagem com o mesmo número.
  def self.words_sem_pdf(words, arquivos, recusas)
    numeros = arquivos.pluck(:chave)
    words.each do |w|
      k = chave(w[:name])
      if k.nil? then recusas << "sem_numero:#{w[:name]}"
      elsif numeros.exclude?(k) then recusas << "word_sem_pdf:#{w[:name]}"
      end
    end
  end
end
