require "rails_helper"

RSpec.describe Csv::Parser do
  let(:utf8_path)  { Rails.root.join("spec/fixtures/csv/rakuten_sample_utf8.csv") }
  let(:sjis_path)  { Rails.root.join("spec/fixtures/csv/rakuten_sample_sjis.csv") }

  describe "format dispatching" do
    it "supports rakuten format" do
      parser = described_class.new(file_path: utf8_path, format: "rakuten")
      expect(parser).to be_an_instance_of(described_class)
    end

    it "raises UnsupportedFormatError for unknown format" do
      expect {
        described_class.new(file_path: utf8_path, format: "unknown_xx")
      }.to raise_error(described_class::UnsupportedFormatError)
    end
  end

  describe "rakuten format parsing" do
    it "parses UTF-8 CSV into hashes" do
      rows = described_class.new(file_path: utf8_path, format: "rakuten").parse
      expect(rows.size).to eq(5)
      expect(rows.first).to include(
        date: Date.new(2026, 4, 1),
        description: "NETFLIX.COM",
        amount: BigDecimal("1490")
      )
    end

    it "parses SJIS CSV (auto-decoded to UTF-8)" do
      rows = described_class.new(file_path: sjis_path, format: "rakuten").parse
      expect(rows.size).to eq(5)
      expect(rows.first[:description]).to eq("NETFLIX.COM")
      expect(rows.last).to include(
        date: Date.new(2026, 4, 15),
        description: "CHATGPT SUBSCRIPTION",
        amount: BigDecimal("3000")
      )
    end

    it "skips rows with missing date / description / amount" do
      Tempfile.create([ "broken", ".csv" ]) do |f|
        f.binmode
        f.write([
          %("利用日","利用店名・商品名","利用金額"),
          %("2026/04/01","NETFLIX","1490"),
          %(",","BLANK_DATE","100"),
          %("2026/04/02",,"600"),
          %("2026/04/03","BAD_AMOUNT","abc")
        ].join("\n"))
        f.flush

        rows = described_class.new(file_path: f.path, format: "rakuten").parse
        # 1 行目の正常データのみ採用される
        expect(rows.size).to eq(1)
        expect(rows.first[:description]).to eq("NETFLIX")
      end
    end

    it "handles comma in amount (e.g. \"1,234\")" do
      Tempfile.create([ "comma", ".csv" ]) do |f|
        f.write([
          %("利用日","利用店名・商品名","利用金額"),
          %("2026/04/01","NETFLIX","1,490")
        ].join("\n"))
        f.flush

        rows = described_class.new(file_path: f.path, format: "rakuten").parse
        expect(rows.first[:amount]).to eq(BigDecimal("1490"))
      end
    end
  end
end
