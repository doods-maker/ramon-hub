# Etapa Documentos (decisão de 07/11): a tese diz se o ganho passa pela etapa Documentos (Ramon::EtapaDeGanho.entrada).
class AddPassaDocumentosToTheses < ActiveRecord::Migration[7.1]
  def change
    add_column :theses, :passa_documentos, :boolean, default: false, null: false
  end
end
