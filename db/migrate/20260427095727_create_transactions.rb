class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :csv_import, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :transaction_date, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description, null: false, limit: 255
      # 抽出済みサブスクとのリンク（PR-C のレビュー画面で関連付け、最初は null）
      t.references :matched_subscription,
                   foreign_key: { to_table: :subscriptions },
                   null: true
      t.integer :classification, null: false, default: 0  # enum: unknown/subscription/non_subscription
      t.integer :classifier  # enum: rule/pattern/ai/user
      t.decimal :confidence, precision: 4, scale: 3  # 0.000 - 1.000
      t.string :inferred_service_name
      t.string :inferred_category

      t.timestamps
    end

    add_index :transactions, [ :user_id, :transaction_date ]
    add_index :transactions, :description
  end
end
