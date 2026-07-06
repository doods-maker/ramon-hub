class AddChannelToLeads < ActiveRecord::Migration[7.1]
  def up
    add_column :leads, :channel, :string
    add_index :leads, :channel

    # Backfill idempotente (WHERE channel IS NULL): mesma classificação do
    # Ramon::SourceCatalog.derive, mais o caso utm (jsonb) -> landing_page.
    execute <<~SQL.squish
      UPDATE leads SET channel = CASE
        WHEN source ~* '^anuncio-meta' THEN 'meta_ads'
        WHEN custom_attributes ? 'utm' THEN 'landing_page'
        WHEN source ~* 'indica' THEN 'indicacao'
        WHEN source ~* 'instagram|\\yig\\y' THEN 'instagram'
        WHEN source ~* 'google|\\yseo\\y' THEN 'google_seo'
        ELSE 'outro'
      END
      WHERE channel IS NULL
    SQL
  end

  def down
    remove_column :leads, :channel
  end
end
