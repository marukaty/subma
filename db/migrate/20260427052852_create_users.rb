class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :firebase_uid, null: false
      t.string :email, null: false
      t.string :display_name
      t.boolean :notification_enabled, null: false, default: true

      t.timestamps
    end
    add_index :users, :firebase_uid, unique: true
    add_index :users, :email
  end
end
