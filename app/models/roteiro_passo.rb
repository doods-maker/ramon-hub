# Um passo do roteiro de qualificação da tese (spec 2026-10-13 §3.1). thesis nil = passo comum da conta, roda antes
# do roteiro de qualquer tese. saidas (avaliadas em ordem, a 1ª que casa vale):
#   [{ 'id', 'quando' (valor, faixa '< 64', resultado da calculadora ou '*'), 'acao', 'alvo' (ir_para),
#      'motivo' (desqualificar/humano), 'motivo_perda' (catálogo lost_reasons; padrão Sem viabilidade),
#      'mensagem' (base da resposta), 'efeitos' => { 'etiqueta', 'etapa' } }]
class RoteiroPasso < ApplicationRecord
  self.table_name = 'ramon_roteiro_passos'

  TIPOS = %w[sim_nao escolha numero data texto].freeze
  ACOES = %w[seguir ir_para desqualificar humano concluir].freeze

  belongs_to :account
  belongs_to :thesis, optional: true

  normalizes :calculadora, with: ->(v) { v.presence }

  validates :titulo, presence: true
  # rubocop:disable Rails/UniqueValidationWithoutIndex -- coberta pelos 2 índices únicos parciais (por tese e comuns)
  validates :chave, presence: true, format: { with: /\A[a-z0-9_]+\z/ }, uniqueness: { scope: %i[account_id thesis_id] }
  # rubocop:enable Rails/UniqueValidationWithoutIndex
  validates :tipo_resposta, inclusion: { in: TIPOS }
  validates :calculadora, inclusion: { in: Ramon::Roteiro::Calculadoras::NOMES }, allow_nil: true
  validate :saidas_validas

  scope :comuns, -> { where(thesis_id: nil) }
  default_scope { order(:position, :id) }

  private

  def saidas_validas
    return errors.add(:saidas, 'deve ser uma lista') unless saidas.is_a?(Array)

    saidas.each.with_index(1) { |saida, n| erros_da_saida(saida).each { |erro| errors.add(:saidas, "#{n}: #{erro}") } }
  end

  def erros_da_saida(saida)
    acao = saida['acao']
    [('falta o id' if saida['id'].blank?),
     ("ação inválida (#{acao})" unless ACOES.include?(acao)),
     ('motivo obrigatório' if %w[desqualificar humano].include?(acao) && saida['motivo'].blank?),
     ('falta o passo de destino' if acao == 'ir_para' && saida['alvo'].blank?),
     erro_motivo_perda(saida['motivo_perda'])].compact
  end

  def erro_motivo_perda(motivo)
    "motivo de perda fora do catálogo (#{motivo})" if motivo_perda_invalido?(motivo)
  end

  def motivo_perda_invalido?(motivo)
    motivo.present? && !account&.lost_reasons&.exists?(name: motivo)
  end
end
