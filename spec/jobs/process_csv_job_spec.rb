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

    describe "再取り込みの重複（ADR-0007）" do
      def new_import(path = csv_path, filename: "again.csv")
        ci = CsvImport.create!(user: user, filename: filename, format: :rakuten, status: :uploading)
        ci.file.attach(io: File.open(path), filename: filename, content_type: "text/csv")
        ci
      end

      it "同じ内容の CSV を 2 回取り込むと、2 回目は transactions が増えず全行スキップになる" do
        described_class.new.perform(csv_import.id)
        second = new_import

        expect {
          expect(described_class.new.perform(second.id)).to eq(:completed)
        }.not_to change(Transaction, :count)

        second.reload
        expect(second.original_row_count).to eq(5)
        expect(second.skipped_duplicate_count).to eq(5)
        expect(second.matched_count).to eq(0)
        expect(second.transactions).to be_empty
        # 既存の取引は最初の取り込みに紐づいたまま
        expect(csv_import.transactions.count).to eq(5)
        expect(csv_import.reload.skipped_duplicate_count).to eq(0)
      end

      it "スキップした行は判定（AI）に渡さない" do
        described_class.new.perform(csv_import.id)
        second = new_import
        ai = Classifiers::AiClassifier.new
        allow(Classifiers::AiClassifier).to receive(:new).and_return(ai)
        allow(ai).to receive(:classify).and_call_original

        described_class.new.perform(second.id)

        expect(ai).to have_received(:classify).with([])
      end

      context "同じ CSV 内に同日・同店・同額の行が 2 つある" do
        let(:dup_csv_path) do
          path = Rails.root.join("tmp/dedup_spec_#{SecureRandom.hex(4)}.csv")
          File.write(path, <<~CSV)
            "利用日","利用店名・商品名","利用者","支払方法","利用金額","支払手数料","支払総額"
            "2026/04/20","SAMPLE CAFE","本人","1回払い","500","0","500"
            "2026/04/20","SAMPLE CAFE","本人","1回払い","500","0","500"
            "2026/04/21","SAMPLE STORE","本人","1回払い","800","0","800"
          CSV
          path
        end

        after { FileUtils.rm_f(dup_csv_path) }

        it "1 回目は両方保存し、2 回目は両方スキップする" do
          first = new_import(dup_csv_path, filename: "dup1.csv")
          described_class.new.perform(first.id)
          expect(first.transactions.where(description: "SAMPLE CAFE").count).to eq(2)
          expect(first.reload.skipped_duplicate_count).to eq(0)

          second = new_import(dup_csv_path, filename: "dup2.csv")
          described_class.new.perform(second.id)
          expect(second.reload.skipped_duplicate_count).to eq(3)
          expect(Transaction.where(user: user, description: "SAMPLE CAFE").count).to eq(2)
        end

        it "保存済みの件数を超えた分だけ保存する（以前の取り込みに 1 件 → 今回の 2 件のうち 1 件を保存）" do
          earlier = CsvImport.create!(user: user, filename: "old.csv", format: :rakuten, status: :completed)
          earlier.transactions.create!(user: user, transaction_date: Date.new(2026, 4, 20),
                                       amount: 500, description: "SAMPLE CAFE")

          ci = new_import(dup_csv_path, filename: "dup.csv")
          described_class.new.perform(ci.id)

          ci.reload
          expect(ci.skipped_duplicate_count).to eq(1)
          expect(ci.transactions.where(description: "SAMPLE CAFE").count).to eq(1)
          expect(ci.transactions.where(description: "SAMPLE STORE").count).to eq(1)
        end
      end

      it "日付・店名・金額のどれかが違えば別の取引として保存する" do
        other = CsvImport.create!(user: user, filename: "old.csv", format: :rakuten, status: :completed)
        other.transactions.create!(user: user, transaction_date: Date.new(2026, 4, 1), amount: 1500, description: "NETFLIX.COM")
        other.transactions.create!(user: user, transaction_date: Date.new(2026, 4, 2), amount: 1490, description: "NETFLIX.COM")
        other.transactions.create!(user: user, transaction_date: Date.new(2026, 4, 1), amount: 1490, description: "NETFLIX")

        described_class.new.perform(csv_import.id)

        expect(csv_import.reload.skipped_duplicate_count).to eq(0)
        expect(csv_import.transactions.count).to eq(5)
      end

      it "他のユーザーの同じ取引は関係ない" do
        other_user = User.create!(firebase_uid: "uid_job_dedup_other", email: "job-dedup-other@example.com")
        other = CsvImport.create!(user: other_user, filename: "o.csv", format: :rakuten, status: :completed)
        other.transactions.create!(user: other_user, transaction_date: Date.new(2026, 4, 1),
                                   amount: 1490, description: "NETFLIX.COM")

        described_class.new.perform(csv_import.id)

        expect(csv_import.reload.skipped_duplicate_count).to eq(0)
        expect(csv_import.transactions.count).to eq(5)
      end

      it "同じ import の再実行では自分の取引をスキップ扱いにせず作り直す" do
        csv_import.transactions.create!(user: user, transaction_date: Date.new(2026, 4, 1),
                                        amount: 1490, description: "NETFLIX.COM")

        described_class.new.perform(csv_import.id)

        expect(csv_import.reload.skipped_duplicate_count).to eq(0)
        expect(csv_import.transactions.count).to eq(5)
      end
    end

    describe "matched_count（サブスク判定の件数）" do
      it "サブスクと判定された行だけを数え、AI の「サブスクではない」・未判定は含めない" do
        ai = Classifiers::AiClassifier.new
        allow(Classifiers::AiClassifier).to receive(:new).and_return(ai)
        allow(ai).to receive(:classify) do |rows|
          by_desc = rows.index_by { |row| row[:description] }
          subscription = by_desc.slice("SPOTIFY P12345").values.map do |row|
            row.merge(classification: "subscription", classifier: "ai", confidence: 0.9)
          end
          not_subscription = by_desc.slice("ENEOS XXXXX", "コンビニATM").values.map do |row|
            row.merge(classification: "non_subscription", classifier: "ai", confidence: 0.9)
          end
          unknown = by_desc.except("SPOTIFY P12345", "ENEOS XXXXX", "コンビニATM").values.map do |row|
            row.merge(classification: "unknown")
          end
          Classifiers::AiClassifier::Result.new(classified: subscription + not_subscription, unclassified: unknown)
        end

        described_class.new.perform(csv_import.id)
        csv_import.reload

        counts = csv_import.transactions.group(:classification).count
        expect(counts).to include("subscription" => 2, "non_subscription" => 2, "unknown" => 1)
        expect(csv_import.matched_count).to eq(2) # NETFLIX（規則）+ SPOTIFY（AI）
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
