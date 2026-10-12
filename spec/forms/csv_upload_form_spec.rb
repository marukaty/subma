require "rails_helper"

RSpec.describe CsvUploadForm do
  let(:csv_path) { Rails.root.join("spec/fixtures/csv/rakuten_sample_utf8.csv") }

  def upload_of(content, filename: "statement.csv", content_type: "text/csv")
    Rack::Test::UploadedFile.new(StringIO.new(content.b), content_type, true, original_filename: filename)
  end

  def form_with(file, format: "rakuten")
    described_class.new(file: file, format: format)
  end

  describe ".supported_formats" do
    it "CsvImport の enum とアダプタの両方にある format だけを返す" do
      expect(described_class.supported_formats).to eq(%w[rakuten])
    end
  end

  describe ".max_bytes" do
    around do |example|
      original = ENV.fetch("CSV_MAX_UPLOAD_BYTES", nil)
      example.run
    ensure
      original.nil? ? ENV.delete("CSV_MAX_UPLOAD_BYTES") : ENV["CSV_MAX_UPLOAD_BYTES"] = original
    end

    it "未設定なら 1MB" do
      ENV.delete("CSV_MAX_UPLOAD_BYTES")
      expect(described_class.max_bytes).to eq(1_048_576)
      expect(described_class.max_size_label).to eq("1MB")
    end

    it "環境変数の値を使う" do
      ENV["CSV_MAX_UPLOAD_BYTES"] = "524288"
      expect(described_class.max_bytes).to eq(524_288)
      expect(described_class.max_size_label).to eq("512KB")
    end

    it "数値でない・0 以下なら既定値に戻す" do
      %w[abc 0 -1 1.5].each do |value|
        ENV["CSV_MAX_UPLOAD_BYTES"] = value
        expect(described_class.max_bytes).to eq(1_048_576), "value=#{value}"
      end
    end
  end

  describe "validations" do
    it "UTF-8 の CSV は有効" do
      expect(form_with(Rack::Test::UploadedFile.new(csv_path, "text/csv"))).to be_valid
    end

    it "BOM 付き UTF-8 も有効" do
      expect(form_with(upload_of("\xEF\xBB\xBF".b + File.binread(csv_path)))).to be_valid
    end

    it "Shift_JIS の CSV は有効" do
      sjis = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/csv/rakuten_sample_sjis.csv"), "text/csv")
      expect(form_with(sjis)).to be_valid
    end

    it "Windows-31J の機種依存文字（①・㈱）を含む CSV も有効" do
      content = "利用日,利用店名・商品名,利用金額\n2026/04/01,㈱①ショップ,100\n".encode(Encoding::Windows_31J)
      expect(form_with(upload_of(content))).to be_valid
    end

    it "text/plain と application/vnd.ms-excel、charset 付きも許可する" do
      %w[text/plain application/vnd.ms-excel text/csv;\ charset=utf-8 TEXT/CSV].each do |type|
        form = form_with(upload_of(File.binread(csv_path), content_type: type))
        expect(form).to be_valid, "content_type=#{type}: #{form.errors.full_messages}"
      end
    end

    it "拡張子は大文字でもよい" do
      expect(form_with(upload_of(File.binread(csv_path), filename: "STATEMENT.CSV"))).to be_valid
    end

    it "NUL バイトを含むファイルは CSV ではないとみなす" do
      form = form_with(upload_of("a,b\n\x00\x01,c\n"))
      expect(form).not_to be_valid
      expect(form.errors.details[:file]).to include(error: :not_csv)
    end

    it "空行だけのファイルは CSV として読み取れないとみなす" do
      form = form_with(upload_of("\n\n\n"))
      expect(form).not_to be_valid
      expect(form.errors.details[:file]).to include(error: :malformed_csv)
    end

    it "先頭だけを読むので、上限内でも大きいファイルの末尾の途中切れで誤判定しない" do
      body = "日付,内容,金額\n" + ("2026/04/01,ネットフリックス,1490\n" * 1_000)
      expect(body.bytesize).to be > described_class::HEAD_BYTES
      expect(form_with(upload_of(body))).to be_valid
    end

    it "検証後もファイルの読み取り位置は先頭に戻っている" do
      file = Rack::Test::UploadedFile.new(csv_path, "text/csv")
      form_with(file).valid?
      expect(file.read).to eq(File.binread(csv_path))
    end
  end

  describe ".max_rows" do
    it "未設定なら 1,000 行" do
      expect(described_class.max_rows).to eq(1_000)
    end

    it "環境変数 CSV_MAX_ROWS の値を使う" do
      with_limit_env("CSV_MAX_ROWS" => "50")
      expect(described_class.max_rows).to eq(50)
    end

    it "数値でない・0 以下なら既定値に戻す" do
      %w[abc 0 -1 1.5].each do |value|
        with_limit_env("CSV_MAX_ROWS" => value)
        expect(described_class.max_rows).to eq(1_000), "value=#{value}"
      end
    end
  end

  describe "行数の上限（M-7）" do
    def csv_with_rows(count, blank_lines: 0)
      "利用日,利用店名・商品名,利用金額\n" +
        Array.new(count) { |i| "2026/04/01,SHOP #{i},100\n" }.join +
        ("\n" * blank_lines)
    end

    it "ヘッダを除いてちょうど上限（1,000 行）なら有効" do
      expect(form_with(upload_of(csv_with_rows(1_000)))).to be_valid
    end

    it "上限を 1 行でも超えると too_many_rows" do
      form = form_with(upload_of(csv_with_rows(1_001)))
      expect(form).not_to be_valid
      expect(form.errors.details[:file]).to include(error: :too_many_rows, max_rows: "1,000")
    end

    it "先頭 16KB より後ろの行も数える" do
      body = csv_with_rows(1_001)
      expect(body.bytesize).to be > described_class::HEAD_BYTES
      expect(form_with(upload_of(body))).not_to be_valid
    end

    it "空行は数えない" do
      expect(form_with(upload_of(csv_with_rows(1_000, blank_lines: 5)))).to be_valid
    end

    it "Shift_JIS の CSV も数える" do
      with_limit_env("CSV_MAX_ROWS" => "3")
      sjis = "利用日,利用店名・商品名,利用金額\n" + ("2026/04/01,コンビニ,100\n" * 4)
      form = form_with(upload_of(sjis.encode(Encoding::Windows_31J)))
      expect(form).not_to be_valid
      expect(form.errors.details[:file]).to include(error: :too_many_rows, max_rows: "3")
    end

    it "CSV_MAX_ROWS で上限を変えられる" do
      with_limit_env("CSV_MAX_ROWS" => "2")
      expect(form_with(upload_of(csv_with_rows(2)))).to be_valid
      expect(form_with(upload_of(csv_with_rows(3)))).not_to be_valid
    end
  end

  describe "#sanitized_filename" do
    it "パス部分を除く" do
      expect(form_with(upload_of("a\n", filename: "C:\\Users\\x\\明細.csv")).sanitized_filename).to eq("明細.csv")
      expect(form_with(upload_of("a\n", filename: "../../etc/x.csv")).sanitized_filename).to eq("x.csv")
    end

    it "100 文字を超える名前は拡張子を残して切る" do
      name = form_with(upload_of("a\n", filename: "#{'あ' * 200}.csv")).sanitized_filename
      expect(name.length).to eq(100)
      expect(name).to end_with(".csv")
    end
  end
end
