module Classifiers
  # Tier 2: パターン検出分類器
  # 同じ店名・同じ金額の取引について、取引日の間隔が「月額相当」または「年額相当」になる
  # ペアを 1 組以上作れたら繰り返し（サブスク候補）とみなし、confidence 0.7 でマークする。
  #
  # ペアの相手は次の 2 つから探す。
  #   (a) ユーザーの過去 transactions
  #       - 月額相当は直近 `lookback_months` ヶ月、年額相当は直近 YEARLY_LOOKBACK_MONTHS ヶ月の履歴
  #   (b) 今回取り込み中の rows 同士（例: 9/15 と 10/15 を 1 ファイルで取り込んだ場合）
  #
  # 同じ日付同士（自分自身や再取り込みで重複した履歴）は間隔 0 日なのでペアにならない。
  # 同月内の偶然の同額（数日差）や、9/30 と 10/2 のような月をまたぐ数日差もペアにならない。
  #
  # 店名の比較は完全一致（履歴側の description は正規化前の文字列で保存されているため。
  # NFKC 正規化での比較は保存時の正規化と合わせて別途対応する。ADR-0004 参照）。
  #
  # マッチしなかった行は unclassified として返す（Tier 3 = AI に渡す対象）。
  class PatternClassifier
    Result = Struct.new(:classified, :unclassified, keyword_init: true)

    DEFAULT_LOOKBACK_MONTHS = 6
    YEARLY_LOOKBACK_MONTHS = 13

    # 取引日の間隔（日数）。周期を増やすときは INTERVAL_RULES に追加する
    # （例: 隔月・3 ヶ月ごとなら 55..65 / 85..95 などを追加）
    MONTHLY_INTERVAL_RANGE = 25..35
    YEARLY_INTERVAL_RANGE = 360..370

    # range: ペアとみなす間隔、lookback_months: 履歴を遡る月数（nil なら lookback_months 引数を使う）
    IntervalRule = Struct.new(:range, :lookback_months, keyword_init: true)
    INTERVAL_RULES = [
      IntervalRule.new(range: MONTHLY_INTERVAL_RANGE, lookback_months: nil),
      IntervalRule.new(range: YEARLY_INTERVAL_RANGE, lookback_months: YEARLY_LOOKBACK_MONTHS)
    ].freeze

    def initialize(user:, lookback_months: DEFAULT_LOOKBACK_MONTHS)
      @user = user
      @lookback_months = lookback_months
    end

    # @param rows [Array<Hash>] [{ date:, description:, amount: }, ...]
    # @return [Result]
    def classify(rows)
      dates_in_rows = dates_by_key(rows)
      classified = []
      unclassified = []

      rows.each do |row|
        if recurring?(row, dates_in_rows)
          classified << row.merge(
            classification: "subscription",
            classifier: "pattern",
            confidence: 0.7,
            inferred_service_name: nil,
            inferred_category: nil
          )
        else
          unclassified << row
        end
      end

      Result.new(classified: classified, unclassified: unclassified)
    end

    private

    def key_for(row)
      [ row[:description], row[:amount] ]
    end

    # 取り込み中の rows を「店名・金額」ごとにまとめ、取引日の配列を返す
    def dates_by_key(rows)
      rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, acc|
        acc[key_for(row)] << row[:date] if row[:date]
      end
    end

    def recurring?(row, dates_in_rows)
      date = row[:date]
      return false if date.nil?

      history = history_dates(row)
      INTERVAL_RULES.any? do |rule|
        since = (rule.lookback_months || @lookback_months).months.ago.to_date
        candidates = dates_in_rows.fetch(key_for(row), []) + history.select { |d| d >= since }
        candidates.any? { |other| rule.range.cover?((date - other).abs) }
      end
    end

    # description・amount で絞り込んだ履歴の取引日（最も長い遡り期間ぶん）
    def history_dates(row)
      since = max_lookback_months.months.ago.to_date
      @user.transactions
           .where(description: row[:description])
           .where(amount: row[:amount])
           .where(transaction_date: since..Date.current)
           .pluck(:transaction_date)
    end

    def max_lookback_months
      INTERVAL_RULES.map { |rule| rule.lookback_months || @lookback_months }.max
    end
  end
end
