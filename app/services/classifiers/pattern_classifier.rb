module Classifiers
  # Tier 2: パターン検出分類器
  # 「同じ店名・同じ金額が、異なる年月に `min_occurrences` 回以上出現」を繰り返し（サブスク候補）とみなし、
  # confidence 0.7 でマークする。判定元は次の 2 つで、どちらかを満たせば候補にする。
  #
  #   1. ユーザーの過去 transactions（直近 `lookback_months` ヶ月）
  #      - 取り込み中の行と同じ日付のレコードは除外する（同じファイルの再取り込みで自分自身に
  #        マッチするのを防ぐ）
  #   2. 今回取り込み中の rows 同士（例: 9 月分と 10 月分を 1 ファイルで取り込んだ場合）
  #
  # どちらも「同じ年月（YYYY-MM）内の複数件は 1 回」と数える。同月内に偶然同額の利用が
  # 2 件あっても繰り返しとはみなさない。
  #
  # 店名の比較は完全一致（履歴側の description は正規化前の文字列で保存されているため。
  # NFKC 正規化での比較は保存時の正規化と合わせて別途対応する。ADR-0004 参照）。
  #
  # マッチしなかった行は unclassified として返す（Tier 3 = AI に渡す対象）。
  class PatternClassifier
    Result = Struct.new(:classified, :unclassified, keyword_init: true)

    DEFAULT_LOOKBACK_MONTHS = 6
    DEFAULT_MIN_OCCURRENCES = 2

    def initialize(user:, lookback_months: DEFAULT_LOOKBACK_MONTHS, min_occurrences: DEFAULT_MIN_OCCURRENCES)
      @user = user
      @lookback_months = lookback_months
      @min_occurrences = min_occurrences
    end

    # @param rows [Array<Hash>] [{ date:, description:, amount: }, ...]
    # @return [Result]
    def classify(rows)
      since = @lookback_months.months.ago.to_date
      months_in_rows = distinct_months_by_key(rows)
      classified = []
      unclassified = []

      rows.each do |row|
        if recurring_in_rows?(row, months_in_rows) || recurring_in_history?(row, since: since)
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

    def month_of(date)
      date.strftime("%Y-%m")
    end

    # 取り込み中の rows を「店名・金額」ごとにまとめ、出現した年月の集合を返す
    def distinct_months_by_key(rows)
      rows.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |row, acc|
        next if row[:date].nil?

        acc[key_for(row)] << month_of(row[:date])
      end
    end

    def recurring_in_rows?(row, months_in_rows)
      months_in_rows.fetch(key_for(row), Set.new).size >= @min_occurrences
    end

    def recurring_in_history?(row, since:)
      scope = @user.transactions
                   .where(description: row[:description])
                   .where(amount: row[:amount])
                   .where(transaction_date: since..Date.current)
      scope = scope.where.not(transaction_date: row[:date]) if row[:date]

      scope.pluck(:transaction_date).map { |d| month_of(d) }.uniq.size >= @min_occurrences
    end
  end
end
