# Um pedido de permissão da esteira de petições, respondido pelo hub (ADR 0014).
# Entrada e caso ("<cliente> #<id>") trazem dado de cliente: ao decidir fica só o número do caso; ao vencer, nada.
class RamonAprovacaoAgente < ApplicationRecord
  self.table_name = 'ramon_aprovacoes_agente'

  class JaDecidida < StandardError; end

  PENDENTE = 'pendente'.freeze
  DECISOES = %w[aprovada negada].freeze
  VALIDADE = 12.hours # igual ao timeout do hook da esteira: depois disso ninguém está esperando
  ENTRADA_MAXIMA = 50_000
  TRECHO_MAXIMO = 4_000 # por campo, quando a entrada passa do teto; cai pela metade até caber
  TRECHO_MINIMO = 50
  LISTA_MAXIMA = 10
  AVISO = 'aviso_hub'.freeze # chave do hub: não é campo de nenhuma ferramenta, e a tela mostra sempre
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
  # O que foi cortado leva a marca no próprio valor: num comando, o fim que não aparece é onde mora o perigo.
  def self.caber(entrada)
    return entrada if entrada.to_json.size <= ENTRADA_MAXIMA

    aviso = { AVISO => 'Entrada grande: o que está marcado [cortado] mostra só o começo. Confira o resto no painel.' }
    trecho = TRECHO_MAXIMO
    while trecho >= TRECHO_MINIMO
      curta = encurtar(entrada, trecho).stringify_keys.merge(aviso) # o teto já conta o aviso
      return curta if curta.to_json.size <= ENTRADA_MAXIMA

      trecho /= 2
    end
    { AVISO => 'Entrada grande demais para mostrar aqui: confira no painel.' } # só chaves já passam do teto
  end

  def self.encurtar(valor, trecho)
    case valor
    when String then valor.size > trecho ? "#{valor.first(trecho)}… [cortado: eram #{valor.size} caracteres]" : valor
    when Hash then valor.transform_values { |v| encurtar(v, trecho) }
    when Array then encurtar_lista(valor, trecho)
    else valor
    end
  end

  def self.encurtar_lista(lista, trecho)
    itens = lista.first(LISTA_MAXIMA).map { |v| encurtar(v, trecho) }
    itens << "… [cortado: +#{lista.size - LISTA_MAXIMA} itens]" if lista.size > LISTA_MAXIMA
    itens
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
