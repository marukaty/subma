# 再取り込みで「既に別の取り込みで保存済み」としてスキップした取引の件数（ADR-0007）。
# あわせて、既存の取り込みの matched_count を「サブスクと判定された取引の件数」に直す
# （これまでは AI が「サブスクではない」と判定した行も数えていた）。
class AddSkippedDuplicateCountToCsvImports < ActiveRecord::Migration[8.1]
  def up
    add_column :csv_imports, :skipped_duplicate_count, :integer, null: false, default: 0

    # classification: 1 = subscription（Transaction.classifications）
    execute <<~SQL.squish
      UPDATE csv_imports
      SET matched_count = (
        SELECT COUNT(*) FROM transactions
        WHERE transactions.csv_import_id = csv_imports.id
          AND transactions.classification = 1
      )
      WHERE csv_imports.matched_count IS NOT NULL
    SQL
  end

  def down
    # matched_count は元の（数え方が誤っていた）値には戻さない
    remove_column :csv_imports, :skipped_duplicate_count
  end
end
