# Metas do comercial: a fonte única é o modelo.mjs (comercial/projetos/operacao-comercial). O exportar-painel.mjs
# gera o mensal.json; subir o arquivo SUBSTITUI todas as metas da conta, para nunca haver duas versões do plano.
# Meta editada à mão no hub não some calada: sem `confirmar`, subir por cima levanta PrecisaConfirmar.
# O liga/desliga ("Usar metas") é mantido na troca.
class Ramon::MetasDoModelo
  class Erro < StandardError; end

  class PrecisaConfirmar < StandardError
    attr_reader :editadas

    def initialize(editadas)
      @editadas = editadas
      super("#{editadas} meta(s) editada(s) à mão serão desfeitas")
    end
  end

  # chave do mensal.json → métrica gravada
  METRICAS = { 'contratos' => 'contratos', 'agendadas' => 'reunioes_agendadas', 'realizadas' => 'reunioes_realizadas',
               'anuncio' => 'gasto_anuncio', 'custo_area' => 'custo_area', 'cac' => 'cac' }.freeze
  MESES = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

  # Devolve o nº de meses gravados.
  def self.importar(account, texto, confirmar: false)
    linhas = JSON.parse(texto.to_s)
    raise Erro, 'esperava a lista do mensal.json' unless linhas.is_a?(Array) && linhas.all?(Hash)

    registros = registros(account, linhas)
    raise Erro, 'nenhuma meta no arquivo' if registros.empty?
    raise Erro, 'mês repetido no arquivo' if linhas.pluck('mes').uniq.size < linhas.size

    substituir(account, registros, confirmar)
    linhas.size
  rescue JSON::ParserError
    raise Erro, 'arquivo não é JSON'
  end

  def self.substituir(account, registros, confirmar)
    atuais = MarketingMeta.where(account_id: account.id)
    editadas = atuais.where.not(editada_em: nil).count
    raise PrecisaConfirmar, editadas if editadas.positive? && !confirmar

    ativa = atuais.exists?(ativa: true)
    MarketingMeta.transaction do
      atuais.delete_all
      MarketingMeta.insert_all!(registros.map { |r| r.merge(ativa: ativa) }) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def self.registros(account, linhas)
    agora = Time.current
    linhas.flat_map do |l|
      mes = mes(l['mes'])
      METRICAS.filter_map do |chave, metrica|
        next if l[chave].nil?
        raise Erro, "#{chave} de #{l['mes']} não é número" unless l[chave].is_a?(Numeric)

        { account_id: account.id, mes: mes, metrica: metrica, valor: l[chave], created_at: agora, updated_at: agora }
      end
    end
  end

  # "Out/26" → 2026-10-01
  def self.mes(texto)
    abrev, ano = texto.to_s.downcase.split('/')
    numero = MESES.index(abrev)
    raise Erro, "mês inválido: #{texto}" if numero.nil? || ano.to_s !~ /\A\d{2}\z/

    Date.new(2000 + ano.to_i, numero + 1, 1)
  end
end
