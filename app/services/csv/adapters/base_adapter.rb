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

      # サブクラスでオーバーライド可能。デフォルトは UTF-8 / SJIS 自動判定。
      def read_rows(file_path)
        text = File.binread(file_path)
        text = decode_to_utf8(text)
        ::CSV.parse(text, headers: true).map(&:to_h)
      end

      # @param row [Hash]
      # @return [Hash, nil]
      def parse_row(row)
        raise NotImplementedError
      end

      private

      UTF8_BOM = "\uFEFF".freeze

      # カード会社の CSV は UTF-8（BOM 付きを含む）と Shift_JIS が混在するため、自動判定して UTF-8 に変換する。
      # File.binread は ASCII-8BIT で返すので、CSV.parse 用に明示的に UTF-8 を立てる。
      # 先頭の BOM を残すと 1 行目が「\uFEFF"利用日"」となり、
      # CSV::MalformedCSVError (Illegal quoting in line 1.) になるため取り除く。
      def decode_to_utf8(text)
        decoded =
          if text.dup.force_encoding("UTF-8").valid_encoding?
            text.force_encoding("UTF-8")
          else
            text.force_encoding("Shift_JIS").encode("UTF-8", invalid: :replace, undef: :replace)
          end
        decoded.delete_prefix(UTF8_BOM)
      end

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
