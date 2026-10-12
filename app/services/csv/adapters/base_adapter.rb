require "csv"

module Csv
  module Adapters
    # CSV アダプタの共通基底クラス。
    # サブクラスは #parse_row(row) を実装し、{ date:, description:, amount: } を返す。
    # 不正な行は nil を返してスキップ可能。
    class BaseAdapter
      class ParseError < StandardError; end

      # @param file_path [String, Pathname]
      # @return [Array<Hash>] [{ date: Date, description: String, amount: BigDecimal }, ...]
      def parse(file_path)
        rows = read_rows(file_path)
        rows.filter_map { |row| parse_row(row) }
      end

      protected

      # サブクラスでオーバーライド可能。デフォルトは UTF-8 / Windows-31J の自動判定（Csv::TextDecoder）。
      def read_rows(file_path)
        text = Csv::TextDecoder.decode(File.binread(file_path))
        ::CSV.parse(text, headers: true).map(&:to_h)
      end

      # @param row [Hash]
      # @return [Hash, nil]
      def parse_row(row)
        raise NotImplementedError
      end

      private

      def parse_amount(str)
        return nil if str.blank?
        # 「1,234」「\1,234」「1234」全て対応、絶対値で扱う（カードは利用額をプラスで持つ仕様の場合あり）
        cleaned = str.to_s.gsub(/[¥,、￥\s]/, "")
        BigDecimal(cleaned)
      rescue ArgumentError, TypeError
        nil
      end

      def parse_date(str)
        return nil if str.blank?
        # "2026/04/01" "2026-04-01" "2026/4/1" などに対応
        Date.parse(str.to_s)
      rescue Date::Error
        nil
      end
    end
  end
end
