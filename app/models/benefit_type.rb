# ponytail: aposentado em 20/10/2026 — a classificação do lead é só a tese (Thesis).
# Nada mais lê/escreve aqui nem em leads.benefit_type_id; tabela e coluna ficam
# até uma migração futura dropar as duas (depois que isto estiver no ar).
class BenefitType < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position) }
end
