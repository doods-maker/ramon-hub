# Caso de teste da IA: uma conversa-modelo do assistente (a última fala é do
# usuário) e o critério do que é resposta boa. A rodada (Captain::IaRodada)
# roda todos os ativos em modo teste — nada é escrito de verdade.
#
# criterios (todos opcionais):
#   deve_usar / nao_deve_usar  ids do config/agents/tools.yml
#   handoff                    sim | nao | indiferente
#   deve_conter / nao_pode_conter  frase (sem acento/caixa) ou /regex/
#   rubrica                    texto livre para o juiz (LLM barato)
class Captain::IaCaso < ApplicationRecord
  self.table_name = 'ramon_ia_casos'

  LISTAS = %w[deve_usar nao_deve_usar deve_conter nao_pode_conter].freeze
  HANDOFF = %w[sim nao indiferente].freeze
  PAPEIS = %w[user assistant].freeze

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'

  validates :titulo, presence: true
  validate :mensagens_validas

  before_validation :normalizar_mensagens
  before_save :normalizar_criterios

  scope :ativos, -> { where(ativo: true) }
  scope :ordenados, -> { order(:grupo, :codigo, :id) }

  def message_history
    mensagens.map { |fala| { role: fala['role'], content: fala['content'].to_s } }
  end

  private

  def normalizar_mensagens
    self.mensagens = Array(mensagens).map { |fala| fala.is_a?(Hash) ? fala.to_h.stringify_keys.slice('role', 'content') : fala }
  end

  def mensagens_validas
    falas = Array(mensagens)
    ok = falas.any? && falas.all? { |fala| fala.is_a?(Hash) && PAPEIS.include?(fala['role']) && fala['content'].present? }
    errors.add(:mensagens, 'precisa de falas user/assistant com texto, terminando no usuário') unless ok && falas.last['role'] == 'user'
  end

  def normalizar_criterios
    dados = (criterios || {}).to_h.stringify_keys
    limpo = LISTAS.index_with { |chave| Array(dados[chave]).map { |item| item.to_s.strip }.compact_blank }
    limpo['handoff'] = HANDOFF.include?(dados['handoff']) ? dados['handoff'] : 'indiferente'
    limpo['rubrica'] = dados['rubrica'].to_s.strip
    self.criterios = limpo
  end
end
