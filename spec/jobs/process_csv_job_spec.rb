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
    # CI では db:prepare 時に seed が走り本物のテンプレートが入っているので、
    # テスト用に確定したマッチ結果を得るため一旦全削除してから登録し直す
    ServiceTemplate.delete_all
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

    it "pending（uploading）→ processing → completed と進み、戻り値は :completed" do
      seen = []
      allow(Csv::Parser).to receive(:new).and_wrap_original do |m, **kw|
        seen << csv_import.reload.status
        m.call(**kw)
      end

      expect(described_class.new.perform(csv_import.id)).to eq(:completed)
      expect(seen).to eq([ "processing" ])
      expect(csv_import.reload.status).to eq("completed")
      expect(csv_import.error_summary).to be_nil
    end

    it "処理後にアップロードファイルを削除する（NFR-S-09）" do
      expect(csv_import.file).to be_attached
      described_class.new.perform(csv_import.id)
      expect(csv_import.reload.file).not_to be_attached
    end

    it "存在しない ID は何もせず :skipped" do
      expect(described_class.new.perform(0)).to eq(:skipped)
    end

    describe "二重実行の防止（ADR-0007）" do
      it "同じ ID で 2 回 perform しても AI 呼び出しは 1 回で、transactions も重複しない" do
        ai = Classifiers::AiClassifier.new
        allow(Classifiers::AiClassifier).to receive(:new).and_return(ai)
        allow(ai).to receive(:classify).and_call_original

        described_class.new.perform(csv_import.id)
        expect(described_class.new.perform(csv_import.id)).to eq(:skipped)

        expect(ai).to have_received(:classify).once
        expect(csv_import.transactions.count).to eq(5)
      end

      %i[processing rule_matching ai_analyzing completed failed].each do |status|
        it "#{status} の import には何もしない（status・transactions・ファイルを変えない）" do
          csv_import.update!(status: status)
          expect(Csv::Parser).not_to receive(:new)
          allow(Rails.logger).to receive(:info).and_call_original
          expect(Rails.logger).to receive(:info).with(/skipped: already #{status}/).and_call_original

          expect(described_class.new.perform(csv_import.id)).to eq(:skipped)

          csv_import.reload
          expect(csv_import.status).to eq(status.to_s)
          expect(csv_import.transactions).to be_empty
          expect(csv_import.file).to be_attached
        end
      end

      it "前回の transactions が残っていても作り直す（import 単位で重複しない）" do
        csv_import.transactions.create!(
          user: user, transaction_date: Date.current, amount: 100, description: "OLD ROW"
        )

        described_class.new.perform(csv_import.id)

        expect(csv_import.transactions.count).to eq(5)
        expect(csv_import.transactions.where(description: "OLD ROW")).to be_empty
      end

      it "他の import の transactions は消さない" do
        other = CsvImport.create!(user: user, filename: "old.csv", format: :rakuten, status: :completed)
        other.transactions.create!(user: user, transaction_date: Date.current, amount: 100, description: "KEEP")

        described_class.new.perform(csv_import.id)

        expect(other.transactions.count).to eq(1)
      end
    end

    describe "1 ユーザー同時 1 件" do
      let!(:running) do
        CsvImport.create!(user: user, filename: "running.csv", format: :rakuten, status: :ai_analyzing)
      end

      it "同じユーザーに処理中の import があれば処理せず :deferred（uploading のまま）" do
        expect(Csv::Parser).not_to receive(:new)
        expect(described_class.new.perform(csv_import.id)).to eq(:deferred)
        expect(csv_import.reload.status).to eq("uploading")
        expect(csv_import.file).to be_attached
      end

      it "処理中のまま止まった（30 分以上更新がない）import は数えない" do
        running.update_columns(updated_at: 31.minutes.ago)
        expect(described_class.new.perform(csv_import.id)).to eq(:completed)
      end

      it "別ユーザーの処理中は関係ない" do
        other_user = User.create!(firebase_uid: "uid_job_other", email: "job-other@example.com")
        running.update!(user: other_user)
        expect(described_class.new.perform(csv_import.id)).to eq(:completed)
      end
    end

    describe "終わったら同じユーザーの待ちを登録する" do
      it "completed のあと、古い順に uploading（ファイルあり）の 1 件を dispatch する" do
        waiting = CsvImport.create!(user: user, filename: "next.csv", format: :rakuten, status: :uploading)
        waiting.file.attach(io: File.open(csv_path), filename: "next.csv", content_type: "text/csv")
        csv_import # 先に作られた import（自分自身）を処理する
        waiting.update_columns(created_at: 1.minute.from_now)

        expect {
          described_class.new.perform(csv_import.id)
        }.to have_enqueued_job(ProcessCsvJob).with(waiting.id).exactly(:once)
      end

      it "待ちが無ければ何も登録しない" do
        expect {
          described_class.new.perform(csv_import.id)
        }.not_to have_enqueued_job(ProcessCsvJob)
      end
    end

    context "when an error occurs in pipeline" do
      before do
        allow(Csv::Parser).to receive(:new).and_raise(ArgumentError, "boom")
      end

      it "例外を外に出さず failed にし、エラーの要約（クラス名）を保存する" do
        expect(described_class.new.perform(csv_import.id)).to eq(:failed)
        csv_import.reload
        expect(csv_import.status).to eq("failed")
        expect(csv_import.error_summary).to eq("ArgumentError")
      end

      it "再処理のためにファイルを削除しない" do
        described_class.new.perform(csv_import.id)
        expect(csv_import.reload.file).to be_attached
      end

      it "failed になった後の再送は何もしない" do
        described_class.new.perform(csv_import.id)
        expect(described_class.new.perform(csv_import.id)).to eq(:skipped)
        expect(Csv::Parser).to have_received(:new).once
      end

      it "再処理で uploading に戻すと、もう一度処理して completed になる" do
        described_class.new.perform(csv_import.id)
        allow(Csv::Parser).to receive(:new).and_call_original

        csv_import.reload.reset_for_retry!
        expect(described_class.new.perform(csv_import.id)).to eq(:completed)

        csv_import.reload
        expect(csv_import.status).to eq("completed")
        expect(csv_import.error_summary).to be_nil
        expect(csv_import.transactions.count).to eq(5)
        expect(csv_import.file).not_to be_attached
      end
    end

    context "when transactions の保存中に失敗する" do
      it "途中まで作った transactions を残さない（ロールバック）" do
        call_count = 0
        allow(Transaction).to receive(:create!).and_wrap_original do |m, *args, **kw|
          call_count += 1
          raise ActiveRecord::RecordInvalid if call_count == 3

          m.call(*args, **kw)
        end

        expect(described_class.new.perform(csv_import.id)).to eq(:failed)
        expect(csv_import.transactions.count).to eq(0)
        expect(csv_import.reload.status).to eq("failed")
      end
    end
  end
end
