module Classifiers
  # Tier 1: 規則ベース分類器
  # ServiceTemplate.match_patterns（正規表現の配列）に対して取引の description を
  # マッチさせ、ヒットしたら subscription として確定する（confidence = 1.0）。
  # マッチしないものは unclassified として返す（後段の Tier 2/3 で処理）。
  #
  # ServiceTemplate を毎回ロードするのを避けるため起動時にメモリにキャッシュする。
  class RuleClassifier
    Result = Struct.new(:classified, :unclassified, keyword_init: true)

    def initialize(templates: ServiceTemplate.all.to_a)
      @templates = templates
    end

    # @param rows [Array<Hash>] [{ date:, description:, amount: }, ...]
    # @return [Result] classified: [{...row, classification:, classifier:, confidence:, ...}, ...]
    #                  unclassified: [{...row}, ...]
    def classify(rows)
      classified = []
      unclassified = []

      rows.each do |row|
        template = match_template(row[:description])
        if template
          classified << row.merge(
            classification: "subscription",
            classifier: "rule",
            confidence: 1.0,
            inferred_service_name: template.service_name,
            inferred_category: template.default_category
          )
        else
          unclassified << row
        end
      end

      Result.new(classified: classified, unclassified: unclassified)
    end

    private

    def match_template(description)
      return nil if description.blank?

      @templates.find { |t| t.match?(description) }
    end
  end
end
