class CreateRamonTheses < ActiveRecord::Migration[7.1]
  def change
    create_table :theses do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.text :description
      t.string :area
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :theses, [:account_id, :name], unique: true

    create_table :thesis_items do |t|
      t.references :thesis, null: false, foreign_key: { on_delete: :cascade }
      t.string :section, null: false
      t.string :title
      t.text :content
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :thesis_items, [:thesis_id, :section, :position]

    add_reference :leads, :thesis, null: true, foreign_key: { on_delete: :nullify }

    reversible do |dir|
      dir.up do
        Account.find_each { |account| Leads::SeedDefaultConfigService.new(account).perform }
      end
    end
  end
end
