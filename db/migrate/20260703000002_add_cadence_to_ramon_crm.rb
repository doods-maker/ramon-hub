class AddCadenceToRamonCrm < ActiveRecord::Migration[7.1]
  DEFAULTS = {
    'Novo' => [10, 2], 'Qualificação' => [20, 3], 'Reunião agendada' => [40, nil],
    'Reunião realizada' => [60, 5], 'Negociação' => [75, 5], 'Última chance' => [50, 7],
    'Fechado' => [100, nil], 'Perdido' => [0, nil]
  }.freeze
  LOST_REASONS = ['Sem viabilidade', 'Sumiu / não respondeu', 'Honorário',
                  'Foi para concorrente', 'Fora da área', 'Outro'].freeze

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def up
    create_table :lead_tasks do |t|
      t.references :account, null: false, index: false
      t.references :lead, null: false
      t.references :user
      t.string :title, null: false
      t.string :kind, null: false, default: 'follow_up'
      t.datetime :due_at, null: false
      t.datetime :completed_at
      t.timestamps
    end
    add_index :lead_tasks, [:account_id, :due_at]
    add_index :lead_tasks, [:lead_id, :completed_at]

    create_table :lost_reasons do |t|
      t.references :account, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_column :lead_stages, :probability, :integer, null: false, default: 0
    add_column :lead_stages, :stalled_after_days, :integer
    add_column :leads, :stage_entered_at, :datetime
    add_column :leads, :won_at, :datetime
    add_column :leads, :lost_at, :datetime

    backfill
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def down
    drop_table :lead_tasks
    drop_table :lost_reasons
    remove_column :lead_stages, :probability
    remove_column :lead_stages, :stalled_after_days
    remove_column :leads, :stage_entered_at
    remove_column :leads, :won_at
    remove_column :leads, :lost_at
  end

  private

  def backfill
    DEFAULTS.each do |name, (probability, stalled)|
      # rubocop:disable Rails/SkipsModelValidations
      LeadStage.where(name: name).update_all(probability: probability, stalled_after_days: stalled)
      # rubocop:enable Rails/SkipsModelValidations
    end
    Account.find_each do |account|
      LOST_REASONS.each_with_index do |name, index|
        LostReason.create!(account_id: account.id, name: name, position: index)
      end
    end
    # stage_entered_at: última transição conhecida ou criação
    execute <<~SQL.squish
      UPDATE leads SET stage_entered_at = COALESCE(
        (SELECT MAX(la.created_at) FROM lead_activities la
          WHERE la.lead_id = leads.id AND la.kind = 'stage_changed'),
        leads.created_at)
    SQL
  end
end
