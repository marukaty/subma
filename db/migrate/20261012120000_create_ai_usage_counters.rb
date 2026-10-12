# AI（Claude API）に送った行数を「ユーザー × 日」と「全体 × 日」で数える（AI 利用料の上限。ADR-0004「利用量の上限」）。
#
# 全体の行は user_id を NULL にする。MySQL の一意インデックスは NULL 同士を別の値として扱うため、
# user_id をそのまま一意キーにすると全体の行が日ごとに 1 行に決まらない。
# そこで NULL を 0 に置き換えた生成列 user_key を作り、(user_key, usage_date) を一意にする。
#
# user_id に外部キー制約は付けない。MySQL では生成列の元になる列に ON DELETE CASCADE の外部キーを
# 付けられず、制約だけ付けるとユーザー削除（退会）がこの表の行で止まるため。
# 行の中身は日付と件数だけなので、ユーザー削除後に残っても個人を特定する情報にはならない。
class CreateAiUsageCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_usage_counters do |t|
      t.references :user, null: true, foreign_key: false
      t.virtual :user_key, type: :bigint, as: "COALESCE(user_id, 0)", stored: true
      t.date :usage_date, null: false
      t.integer :rows_sent, null: false, default: 0
      t.timestamps
    end
    add_index :ai_usage_counters, %i[user_key usage_date], unique: true
  end
end
