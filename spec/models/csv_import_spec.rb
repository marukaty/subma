require "rails_helper"

RSpec.describe CsvImport, type: :model do
  let(:user) { User.create!(firebase_uid: "uid_csv", email: "csv@example.com") }
  let(:valid_attrs) { { user: user, filename: "rakuten_2026_04.csv", format: :rakuten, status: :uploading } }

  describe "validations" do
    it { expect(described_class.new(valid_attrs)).to be_valid }
    it { expect(described_class.new(valid_attrs.merge(filename: nil))).not_to be_valid }
    it { expect(described_class.new(valid_attrs.merge(format: nil))).not_to be_valid }
  end

  describe "enums" do
    it "supports format values" do
      expect(described_class.formats.keys).to match_array(%w[rakuten smcc jcb aeon mufg generic])
    end

    it "supports status values" do
      expect(described_class.statuses.keys).to match_array(
        %w[uploading processing rule_matching ai_analyzing completed failed]
      )
    end
  end

  describe "associations" do
    it "destroys related transactions" do
      ci = described_class.create!(valid_attrs)
      ci.transactions.create!(
        user: user,
        transaction_date: Date.current,
        amount: 1490,
        description: "NETFLIX",
        classification: :unknown
      )
      expect { ci.destroy }.to change(Transaction, :count).by(-1)
    end
  end

  describe "#purge_uploaded_file!" do
    it "no-op when no file attached" do
      ci = described_class.create!(valid_attrs)
      expect { ci.purge_uploaded_file! }.not_to raise_error
    end

    it "purges attached file" do
      ci = described_class.create!(valid_attrs)
      ci.file.attach(
        io: StringIO.new("dummy"),
        filename: "test.csv",
        content_type: "text/csv"
      )
      expect(ci.file).to be_attached
      ci.purge_uploaded_file!
      expect(ci.reload.file).not_to be_attached
    end
  end

  describe "処理中・停止の判定（ADR-0007）" do
    it "processing / rule_matching / ai_analyzing が処理中" do
      %w[processing rule_matching ai_analyzing].each do |st|
        expect(described_class.new(valid_attrs.merge(status: st))).to be_in_progress
      end
      %w[uploading completed failed].each do |st|
        expect(described_class.new(valid_attrs.merge(status: st))).not_to be_in_progress
      end
    end

    it "処理中のまま 30 分以上更新がなければ stale" do
      ci = described_class.create!(valid_attrs.merge(status: :processing))
      expect(ci).not_to be_stale
      ci.update_columns(updated_at: 31.minutes.ago)
      expect(ci).to be_stale
      expect(described_class.actively_processing).not_to include(ci)
    end
  end

  describe "#reset_for_retry!" do
    def with_file(ci)
      ci.file.attach(io: StringIO.new("dummy"), filename: "test.csv", content_type: "text/csv")
      ci
    end

    it "failed をファイルが残っていれば uploading に戻し、error_summary を消す" do
      ci = with_file(described_class.create!(valid_attrs.merge(status: :failed, error_summary: "ArgumentError")))
      ci.reset_for_retry!
      ci.reload
      expect(ci.status).to eq("uploading")
      expect(ci.error_summary).to be_nil
    end

    it "処理中のまま止まったものも戻せる" do
      ci = with_file(described_class.create!(valid_attrs.merge(status: :ai_analyzing)))
      ci.update_columns(updated_at: 31.minutes.ago)
      ci.reset_for_retry!
      expect(ci.reload.status).to eq("uploading")
    end

    %i[uploading processing completed].each do |st|
      it "#{st} は戻せない" do
        ci = with_file(described_class.create!(valid_attrs.merge(status: st)))
        expect { ci.reset_for_retry! }.to raise_error(CsvImport::NotRetryableError)
        expect(ci.reload.status).to eq(st.to_s)
      end
    end

    it "ファイルが残っていなければ戻せない" do
      ci = described_class.create!(valid_attrs.merge(status: :failed))
      expect { ci.reset_for_retry! }.to raise_error(CsvImport::FileMissingError)
      expect(ci.reload.status).to eq("failed")
    end
  end
end
