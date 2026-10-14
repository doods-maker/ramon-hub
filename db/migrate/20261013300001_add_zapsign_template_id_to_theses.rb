# Modelo de contrato do ZapSign por tese (F3 do roteiro): o modo "sozinha até o contrato" só gera o contrato sozinho
# para tese com modelo definido — hoje só existe o de auxílio-acidente (Ramon::ZapsignContractService::TEMPLATE_ID).
class AddZapsignTemplateIdToTheses < ActiveRecord::Migration[7.1]
  def change
    add_column :theses, :zapsign_template_id, :string
  end
end
