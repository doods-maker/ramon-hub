# Extrato da variável de uma pessoa num mês já FECHADO (regulamento §6): o
# payload é a linha do Ramon::ExtratoVariavel como foi apurada — imutável.
class ExtratoFechado < ApplicationRecord
  self.table_name = 'ramon_extratos_fechados'

  belongs_to :account
  belongs_to :user

  validates :papel, inclusion: { in: MetaComercial::PAPEIS }
  validates :competencia, presence: true, uniqueness: { scope: [:account_id, :user_id, :papel] }
end
