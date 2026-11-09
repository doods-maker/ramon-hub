# Contrato apto (regulamento de remuneração §3, decisão 09/11/2026): depois do contrato limpo, o advogado da tese
# valida (apto) ou devolve com motivo; sem resposta em 5 dias úteis o caso fica apto sozinho (apto_por_id nil).
# validacao_desde = início do relógio (o carimbo do limpo, ou o reenvio depois de uma devolução).
# validador_id = advogado designado no lead pelo admin (tese sem advogado fixo, ex.: IR).
# Na tese: quem valida (validador_ids) e a comissão do híbrido por contrato apto (comissao_apto; nil = sem valor).
class AddContratoApto < ActiveRecord::Migration[7.1]
  def change
    change_table :leads, bulk: true do |t|
      t.datetime :validacao_desde
      t.datetime :apto_em
      t.bigint :apto_por_id
      t.datetime :devolvido_em
      t.bigint :devolvido_por_id
      t.text :devolvido_motivo
      t.bigint :validador_id
    end
    change_table :theses, bulk: true do |t|
      t.bigint :validador_ids, array: true, default: [], null: false
      t.decimal :comissao_apto, precision: 8, scale: 2
    end
  end
end
