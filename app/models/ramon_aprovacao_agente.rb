# Um pedido de permissão da esteira de petições, respondido pelo hub (ADR 0014).
# A entrada traz dado de cliente, então é apagada assim que o pedido é decidido ou vence.
class RamonAprovacaoAgente < ApplicationRecord
  self.table_name = 'ramon_aprovacoes_agente'

  class JaDecidida < StandardError; end

  DECISOES = %w[aprovada negada].freeze
  VALIDADE = 12.hours # igual ao timeout do hook da esteira: depois disso ninguém está esperando
  ENTRADA_MAXIMA = 50_000

  belongs_to :decidida_por, class_name: 'User', optional: true

  validates :ferramenta, presence: true
  validates :status, inclusion: { in: ['pendente', *DECISOES] }

  scope :pendentes, -> { where(status: 'pendente').where(created_at: VALIDADE.ago..).order(:id) }

  def self.abrir!(caso:, ferramenta:, entrada:)
    where(status: 'pendente', created_at: ...VALIDADE.ago).delete_all
    entrada = { 'aviso' => 'Entrada grande demais para mostrar aqui: confira no painel.' } if entrada.to_json.size > ENTRADA_MAXIMA
    create!(caso: caso, ferramenta: ferramenta, entrada: entrada)
  end

  def decidir!(decisao, user)
    raise ArgumentError, 'decisão inválida' unless DECISOES.include?(decisao)

    with_lock do
      raise JaDecidida unless status == 'pendente'

      update!(status: decisao, decidida_por: user, decidida_em: Time.current, entrada: {})
    end
  end
end
