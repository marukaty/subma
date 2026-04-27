class BackfillCancelledStatusForPastCancelledAt < ActiveRecord::Migration[8.1]
  # 既存レコードのうち、cancelled_at が今日以前にセットされているのに
  # status が cancelled でないもの（=以前のコードで作成された不整合データ）を
  # cancelled に補正する。
  #
  # 新規保存以降は Subscription#before_save :align_status_with_cancelled_at が
  # 同じ補正をかけるので、本マイグレーションは一度きりの整合性確保。
  #
  # status enum: active=0, paused=1, cancelled=2
  def up
    execute <<~SQL.squish
      UPDATE subscriptions
      SET status = 2, updated_at = NOW()
      WHERE cancelled_at IS NOT NULL
        AND cancelled_at <= CURRENT_DATE
        AND status <> 2
    SQL
  end

  def down
    # 補正を元に戻す手段はない（過去日 cancelled_at + active が正しいユースケースは存在しない）
    raise ActiveRecord::IrreversibleMigration
  end
end
