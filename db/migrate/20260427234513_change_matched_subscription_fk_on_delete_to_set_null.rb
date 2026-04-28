class ChangeMatchedSubscriptionFkOnDeleteToSetNull < ActiveRecord::Migration[8.1]
  # transactions.matched_subscription_id の外部キー制約を ON DELETE SET NULL に変更。
  # 元は RESTRICT のため、対応する Subscription を削除しようとすると 1451 エラーになっていた。
  # Subscription を消しても取引履歴は残し、紐付けだけ外す（履歴データの保護）。
  def up
    remove_foreign_key :transactions, column: :matched_subscription_id
    add_foreign_key :transactions, :subscriptions,
                    column: :matched_subscription_id,
                    on_delete: :nullify
  end

  def down
    remove_foreign_key :transactions, column: :matched_subscription_id
    add_foreign_key :transactions, :subscriptions,
                    column: :matched_subscription_id
  end
end
