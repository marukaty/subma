require "rails_helper"

RSpec.describe ProcessCsvJob, type: :job do
  let(:user) { User.create!(firebase_uid: "uid_job", email: "job@example.com") }
  let(:csv_path) { Rails.root.join("spec/fixtures/csv/rakuten_sample_utf8.csv") }
  let(:csv_import) do
    ci = CsvImport.create!(user: user, filename: "rakuten.csv", format: :rakuten, status: :uploading)
    ci.file.attach(io: File.open(csv_path), filename: "rakuten.csv", content_type: "text/csv")
    ci
  end

  before do
    ServiceTemplate.create!(
      service_name: "TestNetflix_Job",
      default_amount: 1490,
      default_billing_cycle: :monthly,
      default_category: "エンタメ",
      match_patterns: [ "NETFLIX" ]
    )
  end

  describe "#perform" do
    it "ステータスを completed に進めて transactions を作成する" do
      described_class.new.perform(csv_import.id)
      csv_import.reload

      expect(csv_import.status).to eq("completed")
      expect(csv_import.original_row_count).to eq(5)  # fixture の行数
      expect(csv_import.matched_count).to be >= 1     # NETFLIX の規則マッチ
      expect(csv_import.transactions.count).to eq(5)
    end

    it "Tier 1 でマッチした取引が classification: subscription / classifier: rule になる" do
      described_class.new.perform(csv_import.id)
      netflix_tx = csv_import.transactions.find_by(description: "NETFLIX.COM")
      expect(netflix_tx.classification).to eq("subscription")
      expect(netflix_tx.classifier).to eq("rule")
      expect(netflix_tx.inferred_service_name).to eq("TestNetflix_Job")
    end

    it "マッチしなかった取引は classification: unknown のまま保存される" do
      described_class.new.perform(csv_import.id)
      eneos_tx = csv_import.transactions.find_by(description: "ENEOS XXXXX")
      expect(eneos_tx.classification).to eq("unknown")
      expect(eneos_tx.classifier).to be_nil
    end

    it "処理後にアップロードファイルを削除する（NFR-S-09）" do
      expect(csv_import.file).to be_attached
      described_class.new.perform(csv_import.id)
      expect(csv_import.reload.file).not_to be_attached
    end

    context "when an error occurs in pipeline" do
      before do
        allow(Csv::Parser).to receive(:new).and_raise(StandardError, "boom")
      end

      it "ステータスを failed に更新し、ファイルは削除される" do
        expect { described_class.new.perform(csv_import.id) }.to raise_error(StandardError)
        csv_import.reload
        expect(csv_import.status).to eq("failed")
        expect(csv_import.file).not_to be_attached
      end
    end
  end
end
