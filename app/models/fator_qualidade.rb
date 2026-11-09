# Fator de qualidade guardado por pessoa, papel e trimestre (Ramon::FatorTrimestre): calculado uma vez, no trimestre já
# começado, para o extrato não mudar depois. base = a conta que o gestor vê (tipo, numerador, denominador, taxa).
class FatorQualidade < ApplicationRecord
  self.table_name = 'ramon_fatores_trimestre'

  belongs_to :account
  belongs_to :user

  validates :papel, :inicio, :fator, presence: true
end
