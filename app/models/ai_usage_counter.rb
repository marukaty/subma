# AI（Claude API）に送った行数の日次カウンタ（M-7 コスト攻撃対策）。
# user_id があればそのユーザーの行数、NULL なら全ユーザー合計の行数。
# 読み書きは AiUsageLimiter を通す（上限の確認と加算を同じロックの中で行うため）。
class AiUsageCounter < ApplicationRecord
  # 全体の行の user_key（生成列 COALESCE(user_id, 0)）
  GLOBAL_KEY = 0

  belongs_to :user, optional: true

  validates :usage_date, presence: true
  validates :rows_sent, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :global, -> { where(user_key: GLOBAL_KEY) }
end
