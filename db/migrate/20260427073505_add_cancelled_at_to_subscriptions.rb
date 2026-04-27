class AddCancelledAtToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :cancelled_at, :date
  end
end
