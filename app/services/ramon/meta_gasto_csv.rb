# Ponte até a Marketing API ligar: lê o CSV exportado do Gerenciador de Anúncios (nível anúncio, detalhamento
# por Dia, com as colunas de ID) e grava em MetaGasto com origem 'csv'. Aceita cabeçalho em português ou inglês,
# separador , ou ; e decimal com vírgula ou ponto. Linha sem ID de anúncio (ex.: total) é pulada.
require 'csv'

class Ramon::MetaGastoCsv
  class Erro < StandardError; end

  COLUNAS = {
    data: %w[dia day],
    ad_id: ['identificacao do anuncio', 'id do anuncio', 'ad id'],
    ad_name: ['nome do anuncio', 'ad name'],
    adset_id: ['identificacao do conjunto de anuncios', 'id do conjunto de anuncios', 'ad set id'],
    adset_name: ['nome do conjunto de anuncios', 'ad set name'],
    campaign_id: ['identificacao da campanha', 'id da campanha', 'campaign id'],
    campaign_name: ['nome da campanha', 'campaign name'],
    objetivo: %w[objetivo objective],
    spend: ['valor usado', 'amount spent'],
    impressions: %w[impressoes impressions],
    clicks: ['cliques no link', 'link clicks', 'cliques (todos)', 'clicks (all)'],
    resultados: %w[resultados results],
    indicador: ['indicador de resultados', 'result indicator']
  }.freeze
  OBRIGATORIAS = %i[data ad_id spend].freeze

  def self.importar(account, texto)
    new(texto).linhas.then { |linhas| MetaGasto.gravar(account, linhas, origem: 'csv') }
  end

  def initialize(texto)
    @texto = texto.to_s.dup.force_encoding('UTF-8').delete_prefix("\uFEFF")
  end

  def linhas
    tabela = CSV.parse(@texto, headers: true, col_sep: separador)
    indice = indice_das_colunas(tabela.headers)
    tabela.filter_map { |row| linha(row, indice) }
  rescue CSV::MalformedCSVError => e
    raise Erro, "CSV ilegível: #{e.message}"
  end

  private

  def separador
    cabecalho = @texto.lines.first.to_s
    cabecalho.count(';') > cabecalho.count(',') ? ';' : ','
  end

  def indice_das_colunas(headers)
    normalizados = headers.map { |h| normalizar(h) }
    indice = COLUNAS.transform_values do |nomes|
      normalizados.index { |h| nomes.any? { |n| h == n || h.start_with?("#{n} (") } }
    end
    exigir_obrigatorias(indice)
    indice
  end

  def exigir_obrigatorias(indice)
    faltam = OBRIGATORIAS.select { |k| indice[k].nil? }
    return if faltam.empty?

    raise Erro, "Faltam colunas: #{faltam.map { |k| COLUNAS[k].first }.join(', ')}. " \
                'Exporte no nível anúncio, com detalhamento por Dia e a coluna de identificação do anúncio.'
  end

  def normalizar(texto)
    I18n.transliterate(texto.to_s).downcase.strip
  end

  def linha(row, indice)
    v = ->(k) { indice[k] && row[indice[k]].to_s.strip.presence }
    return if v.call(:ad_id).blank?

    texto = %i[ad_id ad_name adset_id adset_name campaign_id campaign_name objetivo].index_with { |k| v.call(k) }
    texto.merge(data: data(v.call(:data)), spend: dinheiro(v.call(:spend)), impressions: inteiro(v.call(:impressions)),
                clicks: inteiro(v.call(:clicks)), **resultados(inteiro(v.call(:resultados)), v.call(:indicador).to_s))
  end

  # "Resultados" do Gerenciador só valem quando o indicador diz o que foi contado.
  def resultados(qtd, indicador)
    { conversas: indicador.include?('messaging_conversation_started') ? qtd : 0,
      leads_meta: indicador.match?(/\blead/) && indicador.exclude?('messaging') ? qtd : 0 }
  end

  def data(texto)
    raise Erro, 'linha sem Dia' if texto.blank?

    texto.include?('/') ? Date.strptime(texto, '%d/%m/%Y') : Date.iso8601(texto)
  rescue Date::Error
    raise Erro, "data inválida: #{texto}"
  end

  # 1.234,56 · 1,234.56 · 1234,56 · 1234.56 → BigDecimal. O último separador é o decimal.
  def dinheiro(texto)
    limpo = texto.to_s.gsub(/[^\d,.-]/, '')
    return BigDecimal(0) if limpo.blank?

    decimal = limpo.rindex(',').to_i > limpo.rindex('.').to_i ? ',' : '.'
    milhar = decimal == ',' ? '.' : ','
    BigDecimal(limpo.delete(milhar).tr(',', '.'))
  end

  def inteiro(texto)
    texto.to_s.gsub(/\D/, '').to_i
  end
end
