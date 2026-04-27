# サービステンプレート（マスターデータ）
# 主要サブスクサービスのデフォルト料金・課金サイクル・カテゴリ・CSV マッチパターンを保持し、
# ユーザーが手動登録時に「テンプレート選択 → 自動入力」で素早く登録できるようにする。
# また CSV 取り込み時の Tier 1 規則ベース判定（Phase 3）でも match_patterns が利用される。
class ServiceTemplate < ApplicationRecord
  enum :default_billing_cycle, {
    monthly: 0,
    yearly: 1,
    weekly: 2,
    custom: 3
  }, prefix: true

  validates :service_name, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :default_billing_cycle, presence: true
  validates :default_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_category, ->(category) { where(default_category: category) }

  # CSV の取引 description にテンプレートのいずれかのパターンがマッチするか
  # @param description [String]
  # @return [Boolean]
  def match?(description)
    Array(match_patterns).any? do |pattern|
      Regexp.new(pattern, Regexp::IGNORECASE).match?(description)
    rescue RegexpError
      false
    end
  end
end
