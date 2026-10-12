# CSV 取り込みが失敗したときの理由（例外クラス名）を残す（ADR-0007）。
# 例外メッセージには CSV の中身が混ざることがあるため、クラス名だけを保存する。
class AddErrorSummaryToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :csv_imports, :error_summary, :string
  end
end
