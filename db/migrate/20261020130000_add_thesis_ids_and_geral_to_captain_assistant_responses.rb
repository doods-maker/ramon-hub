# FAQ por tese real (20/10/2026): a FAQ passa a apontar para as teses da conta (thesis_ids, uma ou várias) ou a ser
# Geral (vale para todo caso). Backfill: o slug antigo (coluna tese) vira os ids das teses da MESMA conta pelo nome;
# 'trabalhista' = todas as "Trabalhista — …". Idempotente: só preenche FAQ com thesis_ids ainda vazio.
# ponytail: a coluna tese fica (ninguém mais lê nem grava); uma migração depois a remove.
class AddThesisIdsAndGeralToCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  # Cópia de Ramon::FaqTeses::SLUGS (migração não depende do código do app). "_" = letra com ou sem acento.
  SLUGS = {
    'auxilio-acidente' => 'Aux_lio-acidente%',
    'auxilio-doenca' => 'Aux_lio por incapacidade tempor_ria%',
    'aposentadoria-invalidez' => 'Aposentadoria por incapacidade permanente%',
    'bpc-loas' => 'BPC%',
    'acrescimo-25' => 'Acr_scimo de 25%',
    'trabalhista' => 'Trabalhista%',
    'isencao-ir' => 'Isen__o de IR%',
    'salario-maternidade' => 'Sal_rio-maternidade%'
  }.freeze

  def up
    add_column :captain_assistant_responses, :thesis_ids, :integer, array: true, default: [], null: false, if_not_exists: true
    add_column :captain_assistant_responses, :geral, :boolean, default: false, null: false, if_not_exists: true
    add_index :captain_assistant_responses, :thesis_ids, using: :gin, if_not_exists: true

    execute "UPDATE captain_assistant_responses SET geral = TRUE WHERE tese = 'geral'"
    SLUGS.each do |slug, padrao|
      execute <<~SQL.squish
        UPDATE captain_assistant_responses r
        SET thesis_ids = ARRAY(SELECT t.id::integer FROM theses t
                               WHERE t.account_id = r.account_id AND t.name ILIKE #{connection.quote(padrao)}
                               ORDER BY t.position, t.id)
        WHERE r.tese = #{connection.quote(slug)} AND r.thesis_ids = '{}'
      SQL
    end
  end

  def down
    remove_index :captain_assistant_responses, :thesis_ids, if_exists: true
    remove_column :captain_assistant_responses, :geral, if_exists: true
    remove_column :captain_assistant_responses, :thesis_ids, if_exists: true
  end
end
