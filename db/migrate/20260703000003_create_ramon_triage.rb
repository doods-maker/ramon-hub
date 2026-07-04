class CreateRamonTriage < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def change
    create_table :triage_agents do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.text :description
      t.string :area, null: false, default: 'previdenciario'
      t.text :system_prompt, null: false
      t.string :provider, null: false, default: 'deepseek'
      t.string :model, null: false, default: 'deepseek-chat'
      t.boolean :sensitive, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :triage_agents, [:account_id, :name], unique: true

    create_table :lead_triages do |t|
      t.references :account, null: false, index: false
      t.references :lead, null: false, foreign_key: { on_delete: :cascade }
      t.references :triage_agent, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: 'pending'
      t.text :result
      t.string :viability
      t.text :error_message
      t.text :source_text
      t.jsonb :kit
      t.string :kit_status, null: false, default: 'pending'
      t.datetime :finished_at
      t.timestamps
    end
    add_index :lead_triages, [:account_id, :status]
    add_index :lead_triages, [:lead_id, :id]

    reversible do |dir|
      dir.up { seed_default_agents }
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

  # Seed inline de propósito: migração não chama service de app que evolui
  # (lição do incidente 03/07 — 000001 × 000002).
  def seed_default_agents
    TriageAgent.reset_column_information
    seed = YAML.safe_load_file(Rails.root.join('db/seeds/ramon/triage_agents_seed.yml'))
    Account.find_each do |account|
      seed['agents'].each do |attrs|
        next if TriageAgent.exists?(account_id: account.id, name: attrs['name'])

        TriageAgent.create!(attrs.merge('account_id' => account.id))
      end
    end
  end
end
