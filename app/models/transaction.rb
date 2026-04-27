# CSV 取り込み済み取引（要件定義書 §4.1 transactions）
# 抽出フェーズの結果を保持し、PR-C のレビュー画面でユーザーが確認・修正後に
# Subscription レコードに変換される。
class Transaction < ApplicationRecord
  belongs_to :csv_import
  belongs_to :user
  # 抽出後に手動で紐付けるため optional
  belongs_to :matched_subscription,
             class_name: "Subscription",
             optional: true

  enum :classification, {
    unknown: 0,
    subscription: 1,
    non_subscription: 2
  }, prefix: true

  enum :classifier, {
    rule: 0,    # Tier 1
    pattern: 1, # Tier 2
    ai: 2,      # Tier 3
    user: 3     # ユーザーが手動で確定/修正
  }, prefix: true

  validates :transaction_date, presence: true
  validates :amount, presence: true, numericality: true
  validates :description, presence: true, length: { maximum: 255 }
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
            allow_nil: true

  scope :subscription_candidates, -> { where(classification: %i[unknown subscription]) }
  scope :for_review, -> { where(classification: :subscription).order(:transaction_date, :description) }
end
