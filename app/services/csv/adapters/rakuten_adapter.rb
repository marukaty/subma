module Csv
  module Adapters
    # 楽天カードの CSV フォーマットを解釈する。
    #
    # 楽天カードの CSV ヘッダ例:
    #   "利用日","利用店名・商品名","利用者","支払方法","利用金額","支払手数料","支払総額","9月支払金額","11月繰越残高","新規サイン"
    #   （「手数料/利息」「10月支払金額」など列名は時期や出力元で変わるが、下記 3 列以外は参照しない）
    #
    # MVP では以下の最低限のカラムのみ参照:
    #   - 利用日 → date
    #   - 利用店名・商品名 → description
    #   - 利用金額 → amount
    #
    # 文字コードは UTF-8（BOM 付き）または Shift_JIS。どちらも BaseAdapter#decode_to_utf8 で自動判定する。
    #
    # 利用日が空で「利用店名・商品名」だけが入った継続行（海外利用の換算レート、ETC の経路など）は
    # 明細ではないため、parse_row が nil を返してスキップする。
    class RakutenAdapter < BaseAdapter
      DATE_COLUMNS = [ "利用日" ].freeze
      DESCRIPTION_COLUMNS = [ "利用店名・商品名", "利用店名" ].freeze
      AMOUNT_COLUMNS = [ "利用金額" ].freeze

      protected

      def parse_row(row)
        date = parse_date(pick(row, DATE_COLUMNS))
        description = pick(row, DESCRIPTION_COLUMNS).to_s.strip
        amount = parse_amount(pick(row, AMOUNT_COLUMNS))

        return nil if date.nil? || description.empty? || amount.nil?

        {
          date: date,
          description: description,
          amount: amount
        }
      end

      private

      def pick(row, candidates)
        candidates.each do |col|
          val = row[col]
          return val if val.present?
        end
        nil
      end
    end
  end
end
