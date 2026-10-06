# Extrato da variável de uma pessoa num mês já FECHADO (regulamento §6): o
# payload é a linha do Ramon::ExtratoVariavel como foi apurada — imutável.
class ExtratoFechado < ApplicationRecord
  self.table_name = 'ramon_extratos_fechados'

  belongs_to :account
  belongs_to :user

  # Registro de ações: quem fechou o mês de quem (o payload fica de fora).
  audited only: %w[user_id papel competencia], associated_with: :account

  validates :papel, inclusion: { in: MetaComercial::PAPEIS }
  validates :competencia, presence: true, uniqueness: { scope: [:account_id, :user_id, :papel] }
end
