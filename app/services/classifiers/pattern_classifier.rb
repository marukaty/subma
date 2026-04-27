module Classifiers
  # Tier 2: パターン検出分類器
  # ユーザーの過去 transactions を参照し、「同店名・同金額が直近 N ヶ月で複数回出現」を
  # 検出して subscription 候補としてマーク（confidence は中程度）。
  #
  # マッチしなかった行は unclassified として返す（Tier 3 = AI に渡す対象）。
  #
  # 過去取引が少ない MVP では当てにならないが、リピート CSV 取り込みで効果を発揮。
  class PatternClassifier
    Result = Struct.new(:classified, :unclassified, keyword_init: true)

    # 過去 N ヶ月以内に同店名・同金額が `min_occurrences` 件以上あればパターン認定
    DEFAULT_LOOKBACK_MONTHS = 3
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
      classified = []
      unclassified = []

      rows.each do |row|
        if recurring_in_history?(row, since: since)
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

    def recurring_in_history?(row, since:)
      count = @user.transactions
                   .where(description: row[:description])
                   .where(amount: row[:amount])
                   .where(transaction_date: since..Date.current)
                   .count
      count >= @min_occurrences
    end
  end
end
