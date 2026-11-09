# Meta individual do mês (Termo de Metas) — o gestor digita na tela Extrato. O papel diz a grade (sdr e closer =
# modelo A; hibrido = modelo B) e vale nos meses seguintes até o gestor lançar outro. `fator` = multiplicador de
# qualidade do trimestre digitado pelo gestor (modelo A; vazio = o calculado). `rampa` ficou sem uso (09/11/2026).
class MetaComercial < ApplicationRecord
  self.table_name = 'ramon_metas_comerciais'

  PAPEIS = [Ramon::Papeis::SDR, Ramon::Papeis::CLOSER, Ramon::Papeis::HIBRIDO].freeze

  belongs_to :account
  belongs_to :user

  # Registro de ações: quem lançou/mudou a meta de quem.
  audited only: %w[user_id papel mes meta fator], associated_with: :account

  validates :papel, inclusion: { in: PAPEIS }
  validates :mes, presence: true, uniqueness: { scope: [:account_id, :user_id] }
  validates :meta, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # vazio = vale o fator calculado do trimestre (Ramon::FatorTrimestre); preenchido = o gestor corrigiu
  validates :fator, numericality: { greater_than: 0, less_than_or_equal_to: 2 }, allow_nil: true
end
