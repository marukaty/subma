require "rails_helper"

RSpec.describe Csv::Parser do
  let(:utf8_path)  { Rails.root.join("spec/fixtures/csv/rakuten_sample_utf8.csv") }
  let(:sjis_path)  { Rails.root.join("spec/fixtures/csv/rakuten_sample_sjis.csv") }
  let(:bom_path)   { Rails.root.join("spec/fixtures/csv/rakuten_utf8_bom.csv") }

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

    context "with UTF-8 BOM (楽天 e-navi のダウンロード形式)" do
      it "fixture starts with the UTF-8 BOM bytes" do
        expect(File.binread(bom_path, 3).bytes).to eq([ 0xEF, 0xBB, 0xBF ])
      end

      it "parses without CSV::MalformedCSVError and maps the first row" do
        rows = described_class.new(file_path: bom_path, format: "rakuten").parse
        expect(rows.size).to eq(4)
        expect(rows.first).to include(
          date: Date.new(2026, 9, 1),
          description: "SAMPLE SHOP",
          amount: BigDecimal("1200")
        )
      end

      it "skips continuation rows that have only 利用店名・商品名 (換算レート / ETC 経路)" do
        rows = described_class.new(file_path: bom_path, format: "rakuten").parse
        expect(rows.map { |r| r[:description] }).to eq(
          [ "SAMPLE SHOP", "SAMPLE OVERSEAS STORE", "SAMPLE ETC", "SAMPLE SUBSCRIPTION" ]
        )
        expect(rows.find { |r| r[:description] == "SAMPLE ETC" }[:amount]).to eq(BigDecimal("1350"))
      end

      it "returns only date / description / amount (ignores 手数料/利息・月名入りの列)" do
        rows = described_class.new(file_path: bom_path, format: "rakuten").parse
        expect(rows).to all(match(date: kind_of(Date), description: kind_of(String), amount: kind_of(BigDecimal)))
      end

      it "strips the BOM even for a minimal file" do
        Tempfile.create([ "bom", ".csv" ]) do |f|
          f.binmode
          f.write("\xEF\xBB\xBF".b + %("利用日","利用店名・商品名","利用金額"\n"2026/09/01","SAMPLE SHOP","500"\n).b)
          f.flush

          rows = described_class.new(file_path: f.path, format: "rakuten").parse
          expect(rows).to eq([ { date: Date.new(2026, 9, 1), description: "SAMPLE SHOP", amount: BigDecimal("500") } ])
        end
      end
    end

    context "with the downloadable sample (public/samples/sample_rakuten.csv)" do
      let(:sample_path) { Rails.root.join("public/samples/sample_rakuten.csv") }

      it "is UTF-8 with BOM and parses all 10 rows" do
        expect(File.binread(sample_path, 3).bytes).to eq([ 0xEF, 0xBB, 0xBF ])

        rows = described_class.new(file_path: sample_path, format: "rakuten").parse
        expect(rows.size).to eq(10)
        expect(rows.first).to eq(date: Date.new(2026, 8, 1), description: "NETFLIX.COM", amount: BigDecimal("1490"))
        expect(rows.map { |r| r[:description] }).to include("SPOTIFY", "AMAZON PRIME 会費")
      end
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
