# AI 判定の上限（M-7）に達して AI に送らなかった行数。画面で「未判定」の理由として表示する
class AddAiSkippedCountToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :csv_imports, :ai_skipped_count, :integer, null: false, default: 0
  end
end
