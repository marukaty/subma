# サービステンプレート（マスターデータ）
# 主要サブスクサービスのデフォルト料金・課金サイクル・カテゴリ・CSV マッチパターンを保持し、
# ユーザーが手動登録時に「テンプレート選択 → 自動入力」で素早く登録できるようにする。
# また CSV 取り込み時の Tier 1 規則ベース判定でも match_patterns が利用される。
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
  #
  # カード会社の CSV は店名が半角カナ（例: 「ｱﾄﾞﾋﾞ」）や全角英数（例: 「ＮＥＴＦＬＩＸ」）で
  # 出力されることがあるため、description とパターンの両方を Unicode NFKC で正規化してから
  # 大文字小文字を無視して照合する（半角カナ → 全角カナ、全角英数 → 半角英数）。
  # match_patterns 自体は従来どおり正規表現の配列として保存し、意味は変えない。
  #
  # @param description [String]
  # @return [Boolean]
  def match?(description)
    normalized = self.class.normalize_for_match(description)
    return false if normalized.empty?

    compiled_patterns.any? { |regexp| regexp.match?(normalized) }
  end

  # 照合用の正規化（NFKC）。nil や不正なバイト列でも例外にしない
  # @param text [String, nil]
  # @return [String]
  def self.normalize_for_match(text)
    text.to_s.scrub("").unicode_normalize(:nfkc)
  end

  private

  # パターンを正規化してコンパイルした結果をキャッシュする（match_patterns が変われば作り直す）。
  # 不正な正規表現は読み飛ばす（1 件の不備で取り込み全体を止めない）
  def compiled_patterns
    patterns = Array(match_patterns)
    return @compiled_patterns if @compiled_patterns_source == patterns

    @compiled_patterns_source = patterns.dup
    @compiled_patterns = patterns.filter_map do |pattern|
      Regexp.new(self.class.normalize_for_match(pattern), Regexp::IGNORECASE)
    rescue RegexpError
      nil
    end
  end
end
