# Peticionamento · Fase 1: petição (pacote de PDFs a protocolar à mão) e seus arquivos.
class CreateRamonPeticoes < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :ramon_peticoes do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.bigint :criado_por_id, null: false
      t.bigint :responsavel_id, null: false
      t.string :numero_processo
      t.string :tribunal, null: false
      t.boolean :inicial, default: false, null: false
      t.date :prazo
      t.string :descricao
      t.string :status, default: 'rascunho', null: false
      t.string :executor, default: 'manual', null: false
      t.string :numero_evento
      t.datetime :protocolada_em
      t.bigint :protocolada_por_id
      t.string :drive_pasta_base_id
      t.string :drive_pasta_id
      t.datetime :arquivada_em
      t.timestamps
      t.index [:account_id, :status]
      t.index [:account_id, :prazo]
      t.index :contact_id
    end

    create_table :ramon_peticao_arquivos do |t|
      t.bigint :peticao_id, null: false
      t.string :nome, null: false
      t.string :tipo, null: false
      t.integer :posicao, null: false
      t.boolean :principal, default: false, null: false
      t.string :origem, null: false
      t.string :drive_origem_id
      t.string :drive_file_id
      t.bigint :tamanho, null: false
      t.timestamps
      t.index [:peticao_id, :posicao]
    end
  end
end
