# Phase 4: CSV 取り込みジョブの起動を環境ごとに振り分けるディスパッチャ
#
# - dev / test:    Sidekiq に enqueue（既存の ProcessCsvJob.perform_later、変更なし）
# - production:    Cloud Tasks に HTTP push タスクを enqueue
#
# 本番では Cloud Tasks → Cloud Run 上の Internal::JobsController#process_csv に POST が飛び、
# 受信側は OIDC ID トークンを検証してから ProcessCsvJob を同期実行する。
#
# 本クラスは Phase 4 PR-A の中核で、PR-B（Terraform）/ PR-C（実デプロイ）と組み合わせて
# Sidekiq + Redis を Cloud Run 単体構成（D-1 構成）に置換するための入り口となる。
#
# 必要な環境変数（production のみ）:
#   GCP_PROJECT_ID         - GCP プロジェクト ID
#   GCP_LOCATION           - Cloud Tasks のロケーション（既定: asia-northeast1）
#   CLOUD_TASKS_QUEUE      - Cloud Tasks キュー名（既定: process-csv）
#   CLOUD_TASKS_TARGET_URL - Cloud Run 上の受信エンドポイント URL
#   CLOUD_TASKS_SA_EMAIL   - Cloud Tasks が OIDC トークンを発行する Service Account のメール
#
# 1 ユーザー同時 1 件（ADR-0007）:
#   同じユーザーに処理中の import があるときは登録を見送り、uploading のまま待たせる。
#   処理中の import が終わると ProcessCsvJob が古い順に次の 1 件を登録する。
#   戻り値は :enqueued（登録した）/ :deferred（見送った）。
#
# [ai-assisted]
class CsvProcessingDispatcher
  # Cloud Tasks がタスク 1 件の応答を待つ時間。Cloud Run のリクエストタイムアウト（900 秒）に合わせる。
  # 指定しないと HTTP タスクの既定は 10 分で、処理中に Cloud Tasks 側だけが諦めて再送してしまう。
  DISPATCH_DEADLINE_SECONDS = 900

  class << self
    def dispatch(csv_import)
      if user_busy?(csv_import)
        Rails.logger.info(
          "CsvProcessingDispatcher: deferred csv_import_id=#{csv_import.id} (another import of the same user is processing)"
        )
        return :deferred
      end

      if use_cloud_tasks?
        enqueue_cloud_task(csv_import.id)
      else
        enqueue_sidekiq(csv_import.id)
      end
      :enqueued
    end

    # 同じユーザーの別の import が処理中か（止まったまま放置されたものは数えない）
    def user_busy?(csv_import)
      CsvImport.actively_processing
               .where(user_id: csv_import.user_id)
               .where.not(id: csv_import.id)
               .exists?
    end

    # production 環境では Cloud Tasks を、それ以外（dev / test）では Sidekiq を使う。
    # クラスメソッドにしてテストから stub しやすくしている。
    def use_cloud_tasks?
      Rails.env.production?
    end

    private

    def enqueue_sidekiq(csv_import_id)
      ProcessCsvJob.perform_later(csv_import_id)
    end

    def enqueue_cloud_task(csv_import_id)
      client = Google::Cloud::Tasks.cloud_tasks
      parent = client.queue_path(
        project: ENV.fetch("GCP_PROJECT_ID"),
        location: ENV.fetch("GCP_LOCATION", "asia-northeast1"),
        queue:    ENV.fetch("CLOUD_TASKS_QUEUE", "process-csv")
      )
      target_url = ENV.fetch("CLOUD_TASKS_TARGET_URL")
      task = {
        http_request: {
          http_method: :POST,
          url: target_url,
          headers: { "Content-Type" => "application/json" },
          body: { csv_import_id: csv_import_id }.to_json,
          oidc_token: {
            service_account_email: ENV.fetch("CLOUD_TASKS_SA_EMAIL"),
            audience: target_url
          }
        },
        dispatch_deadline: { seconds: DISPATCH_DEADLINE_SECONDS }
      }
      client.create_task(parent: parent, task: task)
      Rails.logger.info("CsvProcessingDispatcher: enqueued cloud task csv_import_id=#{csv_import_id}")
    end
  end
end
