# Ação automática do funil (ver Ramon::FunilAutomatico). Ensaio = só registrada, nunca aplicada.
class FunilAcao < ApplicationRecord
  self.table_name = 'ramon_funil_acoes'

  belongs_to :account
  belongs_to :lead
  belongs_to :desfeita_por, class_name: 'User', optional: true

  scope :reais, -> { where(ensaio: false) }
  scope :vivas, -> { reais.where(desfeita_em: nil) }
end
