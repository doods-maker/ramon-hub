# Log auditável de execução das tools do agente (tela Execuções, Fatia 3 da
# área de IA). O instrumentation nativo do Captain só grava com OpenTelemetry
# ligado — que aqui não está — então quem registra é o wrapper de
# Captain::Tools::BasePublicTool#execute.
class Captain::ToolRun < ApplicationRecord
  self.table_name = 'captain_tool_runs'

  # ponytail: teto burro pro resultado não inchar a tabela com dossiê inteiro.
  # Se a tela precisar do texto completo, o upgrade é guardar em outro lugar.
  MAX_RESULTADO = 2_000

  STATUSES = %w[ok erro].freeze

  belongs_to :account

  validates :tool_name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recentes, -> { order(created_at: :desc) }
  # Casos de teste da IA rodam com source 'teste': ficam fora das telas.
  # IS DISTINCT FROM mantém as linhas antigas (source nulo).
  scope :fora_de_teste, -> { where("#{table_name}.source IS DISTINCT FROM 'teste'") }
end
