class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    active_subs = current_user.subscriptions.active.includes(:user)

    @subscription_count = active_subs.count
    @monthly_total = active_subs.sum { |s| s.monthly_amount }
    @yearly_total = active_subs.sum { |s| s.yearly_amount }

    # カテゴリ別の月額合計（円グラフ用）
    @category_breakdown = active_subs.group_by { |s| s.category.presence || "未分類" }
                                     .transform_values { |subs| subs.sum { |s| s.monthly_amount } }
                                     .sort_by { |_, v| -v }
                                     .to_h

    # 直近 12 ヶ月の月間推移（started_at を使った概算）
    @monthly_history = build_monthly_history(active_subs)

    # 今後 30 日の引落予定（サイドリスト用）
    @upcoming = current_user.subscriptions.upcoming(30)

    # 表示中のカレンダー月（クエリで切替可能、デフォルトは今月）
    @calendar_month = parse_calendar_month
    @calendar = build_calendar(@calendar_month)
  end

  private

  # 直近 12 ヶ月、各月末時点で「started_at がその月以前」のサブスクの月額合計を返す
  # @return [Hash<String, BigDecimal>] { "2025-05" => 5400, ... }
  def build_monthly_history(active_subs)
    months = (0..11).map { |i| (i.months.ago).beginning_of_month }.reverse
    months.each_with_object({}) do |month, acc|
      month_end = month.end_of_month
      total = active_subs.select { |s| s.started_at.nil? || s.started_at <= month_end }
                         .sum { |s| s.monthly_amount }
      acc[month.strftime("%Y-%m")] = total
    end
  end

  # クエリパラメータ year / month から表示中のカレンダー月を決定（不正値は今月）
  # @return [Date] その月の 1 日
  def parse_calendar_month
    year = params[:year].to_i
    month = params[:month].to_i

    if year.between?(2000, 2100) && month.between?(1, 12)
      Date.new(year, month, 1)
    else
      Date.current.beginning_of_month
    end
  end

  # 指定月のカレンダーデータ
  # @param month_first [Date] 表示する月の 1 日
  # @return [Hash]
  def build_calendar(month_first)
    last = month_first.end_of_month

    # 表示月にぶつかる引落予定を収集（active のみ。stale な過去予定も含めて表示）
    bills = current_user.subscriptions.active
                        .where(next_billing_date: month_first..last)
                        .order(:next_billing_date, :service_name)
    by_date = bills.group_by(&:next_billing_date)

    # 月初の前の空白日 + 月末以降の空白日でカレンダー枠を作る
    leading_blanks = month_first.wday  # 日曜=0
    trailing_blanks = 6 - last.wday
    days = Array.new(leading_blanks, nil) + (month_first..last).to_a + Array.new(trailing_blanks, nil)
    weeks = days.each_slice(7).to_a

    {
      weeks: weeks,
      by_date: by_date,
      today: Date.current,
      first: month_first,
      prev_month: month_first.prev_month,
      next_month: month_first.next_month
    }
  end
end
