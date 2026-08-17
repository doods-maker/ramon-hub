# Trilha de cada execução do agente do hub (Claude na VPS): pedido, status,
# resumo e ações determinísticas feitas pelo runner. Alimenta o Metabase.
class AgenteExecucao < ApplicationRecord
  # "execucao" não pluraliza em inglês: o Rails inferiria agente_execucaos.
  self.table_name = 'agente_execucoes'

  STATUS = %w[ok erro limite cap timeout].freeze

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :lead, optional: true

  validates :pedido, presence: true
  validates :status, inclusion: { in: STATUS }
end
