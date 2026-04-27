class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :filename, null: false
      t.integer :format, null: false  # enum: rakuten/smcc/jcb/aeon/mufg/generic
      t.integer :status, null: false, default: 0  # enum: uploading/processing/rule_matching/ai_analyzing/completed/failed
      t.integer :original_row_count
      t.integer :matched_count

      t.timestamps
    end

    add_index :csv_imports, [ :user_id, :created_at ]
  end
end
