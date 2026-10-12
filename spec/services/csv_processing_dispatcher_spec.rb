require "rails_helper"

RSpec.describe CsvProcessingDispatcher do
  let(:user) { User.create!(firebase_uid: "uid_dispatcher", email: "dispatcher@example.com") }
  let(:csv_import) do
    user.csv_imports.create!(filename: "x.csv", format: :rakuten, status: :uploading)
  end

  describe ".dispatch" do
    context "test 環境（既定）" do
      it "ProcessCsvJob を enqueue する（Sidekiq 経路）" do
        expect {
          described_class.dispatch(csv_import)
        }.to have_enqueued_job(ProcessCsvJob).with(csv_import.id)
      end

      it "Google::Cloud::Tasks を呼ばない" do
        expect(Google::Cloud::Tasks).not_to receive(:cloud_tasks)
        described_class.dispatch(csv_import)
      end

      it ":enqueued を返す" do
        expect(described_class.dispatch(csv_import)).to eq(:enqueued)
      end
    end

    context "同じユーザーに処理中の import がある（ADR-0007: 1 ユーザー同時 1 件）" do
      %i[processing rule_matching ai_analyzing].each do |status|
        it "#{status} があれば登録せず :deferred を返す（uploading のまま）" do
          user.csv_imports.create!(filename: "running.csv", format: :rakuten, status: status)

          expect {
            expect(described_class.dispatch(csv_import)).to eq(:deferred)
          }.not_to have_enqueued_job(ProcessCsvJob)
          expect(csv_import.reload.status).to eq("uploading")
        end
      end

      it "処理中のまま 30 分以上止まっている import は数えない" do
        running = user.csv_imports.create!(filename: "running.csv", format: :rakuten, status: :processing)
        running.update_columns(updated_at: 31.minutes.ago)

        expect {
          described_class.dispatch(csv_import)
        }.to have_enqueued_job(ProcessCsvJob).with(csv_import.id)
      end

      it "完了・失敗の import は数えない" do
        user.csv_imports.create!(filename: "done.csv", format: :rakuten, status: :completed)
        user.csv_imports.create!(filename: "ng.csv", format: :rakuten, status: :failed)

        expect(described_class.dispatch(csv_import)).to eq(:enqueued)
      end

      it "別ユーザーの処理中は関係ない" do
        other = User.create!(firebase_uid: "uid_dispatcher_other", email: "dispatcher-other@example.com")
        other.csv_imports.create!(filename: "running.csv", format: :rakuten, status: :processing)

        expect(described_class.dispatch(csv_import)).to eq(:enqueued)
      end
    end

    context "production 経路（use_cloud_tasks? を stub）" do
      let(:fake_tasks_client) { instance_double("Google::Cloud::Tasks::V2::CloudTasks::Client") }

      before do
        allow(described_class).to receive(:use_cloud_tasks?).and_return(true)
        allow(Google::Cloud::Tasks).to receive(:cloud_tasks).and_return(fake_tasks_client)
        allow(fake_tasks_client).to receive(:queue_path).and_return("projects/p/locations/asia-northeast1/queues/process-csv")
        allow(fake_tasks_client).to receive(:create_task)

        ENV["GCP_PROJECT_ID"]         = "test-project"
        ENV["GCP_LOCATION"]           = "asia-northeast1"
        ENV["CLOUD_TASKS_QUEUE"]      = "process-csv"
        ENV["CLOUD_TASKS_TARGET_URL"] = "https://example.com/internal/jobs/process_csv"
        ENV["CLOUD_TASKS_SA_EMAIL"]   = "sa@test-project.iam.gserviceaccount.com"
      end

      after do
        %w[GCP_PROJECT_ID GCP_LOCATION CLOUD_TASKS_QUEUE CLOUD_TASKS_TARGET_URL CLOUD_TASKS_SA_EMAIL].each { |k| ENV.delete(k) }
      end

      it "ProcessCsvJob を enqueue しない" do
        expect {
          described_class.dispatch(csv_import)
        }.not_to have_enqueued_job(ProcessCsvJob)
      end

      it "Google::Cloud::Tasks に create_task を呼ぶ" do
        expect(fake_tasks_client).to receive(:create_task) do |args|
          expect(args[:parent]).to include("queues/process-csv")
          http_request = args[:task][:http_request]
          expect(http_request[:http_method]).to eq(:POST)
          expect(http_request[:url]).to eq("https://example.com/internal/jobs/process_csv")
          body = JSON.parse(http_request[:body])
          expect(body["csv_import_id"]).to eq(csv_import.id)
          expect(http_request[:oidc_token][:audience]).to eq("https://example.com/internal/jobs/process_csv")
          expect(http_request[:oidc_token][:service_account_email]).to eq("sa@test-project.iam.gserviceaccount.com")
          # Cloud Run の timeout（900 秒）と同じ待ち時間を指定する（ADR-0007）
          expect(args[:task][:dispatch_deadline]).to eq(seconds: 900)
        end

        described_class.dispatch(csv_import)
      end

      it "必須環境変数（CLOUD_TASKS_TARGET_URL）が無いと KeyError" do
        ENV.delete("CLOUD_TASKS_TARGET_URL")
        expect { described_class.dispatch(csv_import) }.to raise_error(KeyError)
      end
    end
  end

  describe ".use_cloud_tasks?" do
    it "test 環境では false" do
      expect(described_class.use_cloud_tasks?).to be(false)
    end
  end
end
