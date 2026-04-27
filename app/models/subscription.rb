class Subscription < ApplicationRecord
  belongs_to :user

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
end
