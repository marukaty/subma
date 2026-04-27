class CreateServiceTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :service_templates do |t|
      t.string :service_name, null: false
      t.decimal :default_amount, precision: 10, scale: 2
      t.integer :default_billing_cycle, null: false, default: 0  # enum: monthly/yearly/weekly/custom
      t.string :default_category
      t.json :match_patterns
      t.string :icon_url

      t.timestamps
    end

    add_index :service_templates, :service_name, unique: true
    add_index :service_templates, :default_category
  end
end
