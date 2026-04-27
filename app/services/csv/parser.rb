module Csv
  # CSV パーサのファサード。フォーマット指定でアダプタをディスパッチする。
  #
  # @example
  #   rows = Csv::Parser.new(file_path: "/tmp/rakuten.csv", format: "rakuten").parse
  #   rows.each { |r| puts "#{r[:date]} #{r[:description]} #{r[:amount]}" }
  class Parser
    ADAPTERS = {
      "rakuten" => Csv::Adapters::RakutenAdapter
      # PR-B 以降で smcc / jcb / aeon / mufg / generic を追加
    }.freeze

    class UnsupportedFormatError < StandardError; end

    # @param file_path [String, Pathname]
    # @param format [String] "rakuten" など
    def initialize(file_path:, format:)
      @file_path = file_path
      adapter_class = ADAPTERS[format.to_s]
      raise UnsupportedFormatError, "unknown format: #{format}" unless adapter_class

      @adapter = adapter_class.new
    end

    # @return [Array<Hash>] [{ date:, description:, amount: }, ...]
    def parse
      @adapter.parse(@file_path)
    end
  end
end
