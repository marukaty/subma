class Subscription < ApplicationRecord
  belongs_to :user

  # CSV 取り込みのレビュー画面で「このサブスクとして登録した」と紐付けた transactions。
  # サブスクを削除しても取引履歴自体は残し、紐付けだけ外す（dependent: :nullify）。
  has_many :matched_transactions,
           class_name: "Transaction",
           foreign_key: :matched_subscription_id,
           inverse_of: :matched_subscription,
           dependent: :nullify

  enum :billing_cycle, {
    monthly: 0,
    yearly: 1,
    weekly: 2,
    custom: 3
  }, prefix: true

  enum :status, {
    active: 0,
    paused: 1,
    cancelled: 2
  }, prefix: true

  enum :source, {
    manual: 0,
    csv: 1,
    ai: 2
  }, prefix: true

  validates :service_name, presence: true, length: { maximum: 100 }
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validates :billing_cycle, presence: true
  validates :status, presence: true
  validates :source, presence: true
  validates :memo, length: { maximum: 1000 }, allow_blank: true

  # cancelled_at が今日以前にセットされている場合は status を cancelled に自動補正する。
  # 過去日の解約データを active のまま登録すると一覧の状態とアクションボタンが
  # 不整合になるため、保存時に整合性を担保する。
  # 未来の cancelled_at（解約予約）は active を維持する。
  before_save :align_status_with_cancelled_at

  scope :active,    -> { where(status: :active) }
  scope :paused,    -> { where(status: :paused) }
  scope :cancelled, -> { where(status: :cancelled) }
  scope :upcoming, ->(days = 30) {
    active.where(next_billing_date: Date.current..(Date.current + days.days)).order(:next_billing_date)
  }

  # 月額換算した金額（年額 → 12 で割る、週額 → 4.345 倍）
  # @return [BigDecimal]
  def monthly_amount
    case billing_cycle
    when "monthly" then amount
    when "yearly"  then (amount / 12).round(2)
    when "weekly"  then (amount * BigDecimal("4.345")).round(2)
    else amount # custom: 月額相当として扱う（後で改善）
    end
  end

  # 年額換算した金額
  # @return [BigDecimal]
  def yearly_amount
    case billing_cycle
    when "monthly" then amount * 12
    when "yearly"  then amount
    when "weekly"  then (amount * 52).round(2)
    else amount * 12
    end
  end

  private

  def align_status_with_cancelled_at
    return if cancelled_at.blank?
    return if cancelled_at > Date.current

    self.status = :cancelled unless status_cancelled?
  end
end
