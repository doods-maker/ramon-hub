# Uma chamada de LLM do hub (tela Uso e custo). Gravada só por Ramon::LlmUso —
# nunca na mão. custo_usd nil = modelo sem preço na tabela do RubyLLM.
class LlmChamada < ApplicationRecord
  self.table_name = 'ramon_llm_chamadas'

  STATUS = %w[ok erro].freeze

  belongs_to :account

  validates :funcao, presence: true
  validates :status, inclusion: { in: STATUS }

  # Ator do sino do alerta de gasto (Notification exige primary_actor com estes dois).
  def name = 'IA'

  def push_event_data
    { id: id, funcao: funcao, model: model, custo_usd: custo_usd&.to_f }
  end
end
