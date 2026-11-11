# Data/hora vinda de parâmetro de filtro (Kanban, Agenda): só String que o parse entende.
# Qualquer outra coisa (lixo, array, string gigante, vazio) responde 422 DATA_INVALIDA em vez de 500.
module ParametroDeData
  extend ActiveSupport::Concern

  class Invalida < StandardError; end

  included do
    rescue_from(Invalida) { render json: { error: 'DATA_INVALIDA' }, status: :unprocessable_entity }
  end

  private

  def data_do_parametro(chave) = converter_parametro(chave) { |valor| Date.parse(valor) }

  def hora_do_parametro(chave) = converter_parametro(chave) { |valor| Time.zone.parse(valor) }

  # Time.zone.parse devolve nil para texto que não é data; Date.parse levanta (Date::Error é ArgumentError).
  def converter_parametro(chave)
    valor = params[chave]
    raise Invalida unless valor.is_a?(String)

    yield(valor) || raise(Invalida)
  rescue ArgumentError, TypeError
    raise Invalida
  end
end
