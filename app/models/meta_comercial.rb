# Meta individual do mês (Termo de Metas) — o gestor digita na tela Extrato.
# `rampa` = meses 1–2 do contratado (garantia mínima, regulamento §7).
class MetaComercial < ApplicationRecord
  self.table_name = 'ramon_metas_comerciais'

  PAPEIS = [Ramon::Papeis::SDR, Ramon::Papeis::CLOSER].freeze

  belongs_to :account
  belongs_to :user

  # Registro de ações: quem lançou/mudou a meta de quem.
  audited only: %w[user_id papel mes meta rampa], associated_with: :account

  validates :papel, inclusion: { in: PAPEIS }
  validates :mes, presence: true, uniqueness: { scope: [:account_id, :user_id] }
  validates :meta, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
