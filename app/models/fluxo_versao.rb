# Foto publicada do desenho de um Fluxo. Nunca é editada depois de criada.
class FluxoVersao < ApplicationRecord
  self.table_name = 'ramon_fluxo_versoes'

  belongs_to :fluxo
end
