module Csv
  module Adapters
    # 楽天カードの CSV フォーマットを解釈する。
    #
    # 楽天カードの CSV ヘッダ例:
    #   "利用日","利用店名・商品名","利用者","支払方法","利用金額","支払手数料","支払総額","9月支払金額","11月繰越残高","新規サイン"
    #
    # MVP では以下の最低限のカラムのみ参照:
    #   - 利用日 → date
    #   - 利用店名・商品名 → description
    #   - 利用金額 → amount
    #
    # 楽天は SJIS 出力なので BaseAdapter#decode_to_utf8 で変換される。
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
