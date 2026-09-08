# lib/ramon/portal_texto.rb
# Tradução do ADVBOX para a língua do cliente (config/ramon/portal_etapas.yml).
# Calculado no render: mudar o YAML não exige re-sincronizar o espelho.
module Ramon::PortalTexto
  DADOS = YAML.load_file(Rails.root.join('config/ramon/portal_etapas.yml')).freeze
  ETAPAS = DADOS['etapas'].freeze
  MARCOS = DADOS['marcos'].map { |m| m.merge('re' => Regexp.new(m['regex'], Regexp::IGNORECASE)) }.freeze
  FASE_ENCERRADA = 'ARQUIVAMENTO'.freeze

  module_function

  def normalizar(str)
    I18n.transliterate(str.to_s).upcase.squish
  end

  def etapa(stage)
    return { 'titulo' => 'Em andamento', 'o_que_esperar' => 'Nossa equipe está cuidando do seu caso.' } if stage.blank?

    ETAPAS[normalizar(stage)] || { 'titulo' => stage.to_s.downcase.capitalize,
                                   'o_que_esperar' => 'Nossa equipe está cuidando desta etapa. Avisamos você a cada avanço.' }
  end

  # andamentos: [{ 'data' => 'YYYY-MM-DD', 'titulo' => }] em qualquer ordem.
  def marcos(andamentos)
    por_tipo = {}
    Array(andamentos).sort_by { |a| a['data'].to_s }.each do |a|
      texto = I18n.transliterate(a['titulo'].to_s)
      marco = MARCOS.find { |m| m['re'].match?(texto) }
      next unless marco

      por_tipo[marco['tipo']] = { 'data' => a['data'], 'tipo' => marco['tipo'],
                                  'titulo' => marco['titulo'], 'explicacao' => marco['explicacao'] }
    end
    por_tipo.values.sort_by { |m| m['data'].to_s }
  end

  def encerrado?(step)
    normalizar(step) == FASE_ENCERRADA
  end
end
