# Um pedido de permissão da esteira de petições, respondido pelo hub (ADR 0014).
# Entrada e caso ("<cliente> #<id>") trazem dado de cliente: ao decidir fica só o número do caso; ao vencer, nada.
class RamonAprovacaoAgente < ApplicationRecord
  self.table_name = 'ramon_aprovacoes_agente'

  class JaDecidida < StandardError; end

  PENDENTE = 'pendente'.freeze
  DECISOES = %w[aprovada negada].freeze
  VALIDADE = 12.hours # igual ao timeout do hook da esteira: depois disso ninguém está esperando
  ENTRADA_MAXIMA = 50_000
  TRECHO_MAXIMO = 4_000 # por campo, quando a entrada passa do teto
  LISTA_MAXIMA = 10
  MOTIVO_MAXIMO = 1000

  belongs_to :decidida_por, class_name: 'User', optional: true

  validates :ferramenta, presence: true
  validates :status, inclusion: { in: [PENDENTE, *DECISOES] }

  scope :pendentes, -> { where(status: PENDENTE).where(created_at: VALIDADE.ago..).order(:id) }

  def self.abrir!(caso:, ferramenta:, entrada:)
    where(status: PENDENTE, created_at: ...VALIDADE.ago).delete_all
    where(decidida_em: ...VALIDADE.ago).where.not(motivo: nil).update_all(motivo: nil) # rubocop:disable Rails/SkipsModelValidations
    create!(caso: caso.to_s.truncate(200), ferramenta: ferramenta.to_s.truncate(200), entrada: caber(entrada))
  end

  # Entrada acima do teto: fica o começo de cada campo (quem decide precisa ler o comando, o caminho, o início da peça).
  def self.caber(entrada)
    return entrada if entrada.to_json.size <= ENTRADA_MAXIMA

    curta = encurtar(entrada)
    return { 'aviso' => 'Entrada grande demais para mostrar aqui: confira no painel.' } if curta.to_json.size > ENTRADA_MAXIMA

    curta.merge('aviso' => 'Entrada grande: cada campo mostra só o começo. Confira o resto no painel.')
  end

  def self.encurtar(valor)
    case valor
    when String then valor.truncate(TRECHO_MAXIMO)
    when Hash then valor.transform_values { |v| encurtar(v) }
    when Array then valor.first(LISTA_MAXIMA).map { |v| encurtar(v) }
    else valor
    end
  end

  def decidir!(decisao, user, motivo: nil)
    raise ArgumentError, 'decisão inválida' unless DECISOES.include?(decisao)

    with_lock do
      raise JaDecidida unless status == PENDENTE

      update!(status: decisao, decidida_por: user, decidida_em: Time.current, entrada: {}, caso: caso.to_s[/\d+\z/],
              motivo: decisao == 'negada' ? motivo.to_s.strip.truncate(MOTIVO_MAXIMO).presence : nil)
    end
  end

  # O motivo pode citar o cliente: vai uma vez para o hook e some, como a entrada.
  def entregar_motivo!
    motivo.tap { update!(motivo: nil) if motivo }
  end
end
