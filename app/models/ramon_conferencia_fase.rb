# Conferência de fases (tela do hub): 1 processo judicial ativo do ADVBOX — a etapa de lá, o que o Painel do
# Cliente mostra (Ramon::PortalTexto.etapa_real, pelo tribunal e pelas tarefas), a etapa sugerida e a marcação da
# equipe. Refeita à noite pelo Ramon::ConferenciaFasesJob; o administrador aplica as marcadas no ADVBOX.
class RamonConferenciaFase < ApplicationRecord
  self.table_name = 'ramon_conferencias_fase'

  # atrasada = tribunal à frente da etapa · baixa = tribunal encerrou · diferente = fase diferente sem andamento
  # que decida · igual = mesma fase.
  GRUPOS = %w[atrasada baixa diferente igual].freeze
  MARCAS = %w[certo errado].freeze

  belongs_to :account
  belongs_to :marcado_por, class_name: 'User', optional: true
  belongs_to :aplicado_por, class_name: 'User', optional: true

  validates :lawsuit_id, presence: true, uniqueness: { scope: :account_id }
  validates :grupo, inclusion: { in: GRUPOS }
  validates :painel_marca, inclusion: { in: MARCAS }, allow_nil: true

  scope :para_aplicar, -> { where(atualizar: true, aplicado_em: nil).where.not(sugestao: nil) }
end
