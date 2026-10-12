require "rails_helper"

RSpec.describe Csv::TextDecoder do
  describe ".decode" do
    it "UTF-8 はそのまま返す" do
      expect(described_class.decode("利用日,NETFLIX\n".b)).to eq("利用日,NETFLIX\n")
    end

    it "先頭の BOM を取り除く" do
      expect(described_class.decode("\xEF\xBB\xBF".b + "利用日".b)).to eq("利用日")
    end

    it "Windows-31J の機種依存文字（①・㈱・髙）を化けずに読む" do
      bytes = "①㈱髙島屋".encode(Encoding::Windows_31J).b

      decoded = described_class.decode(bytes)
      expect(decoded).to eq("①㈱髙島屋")
      expect(decoded.encoding).to eq(Encoding::UTF_8)
      expect(described_class.decode(bytes, strict: true)).to eq("①㈱髙島屋")
    end

    it "strict: true では、どちらの文字コードとしても読めなければ nil" do
      expect(described_class.decode("\x81\x00\xFF".b, strict: true)).to be_nil
    end

    it "strict: false では、読めないバイトを置き換えて返す" do
      decoded = described_class.decode("ABC\x81\x00".b)
      expect(decoded).to start_with("ABC")
      expect(decoded).to be_valid_encoding
    end
  end
end
