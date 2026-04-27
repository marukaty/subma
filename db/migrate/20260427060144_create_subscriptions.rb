class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :service_name, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false, default: "JPY", limit: 3
      t.integer :billing_cycle, null: false, default: 0  # enum: monthly/yearly/weekly/custom
      t.date :next_billing_date
      t.string :payment_method
      t.string :category
      t.integer :status, null: false, default: 0  # enum: active/paused/cancelled
      t.date :started_at
      t.text :memo
      t.integer :source, null: false, default: 0  # enum: manual/csv/ai

      t.timestamps
    end

    add_index :subscriptions, [ :user_id, :status ]
    add_index :subscriptions, :next_billing_date
  end
end
