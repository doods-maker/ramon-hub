# Operação SDR + Closer (playbook operacional §13, itens 4–5): reunião
# qualificada marcada pelo Closer e carimbos do contrato limpo.
class AddComercialFieldsToLeads < ActiveRecord::Migration[7.1]
  def change
    change_table :leads, bulk: true do |t|
      t.string :reuniao_resultado
      t.datetime :reuniao_registrada_em
      t.datetime :docs_completos_em
      t.datetime :contrato_limpo_em
    end
  end
end
