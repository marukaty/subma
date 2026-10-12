# 失敗した（または処理中のまま止まった）CSV 取り込みを再処理する（ADR-0007）
#
# POST /csv_imports/:csv_import_id/retry
#   - 本人の import だけ（他人の ID は 404）
#   - failed / 止まった processing → uploading に戻してから CsvProcessingDispatcher で登録
#   - アップロードファイルが残っていない場合は再アップロードを案内する
module CsvImports
  class RetriesController < ApplicationController
    before_action :authenticate_user!

    def create
      csv_import = current_user.csv_imports.find(params[:csv_import_id])
      @audit_resource = csv_import

      csv_import.reset_for_retry!
      result = CsvProcessingDispatcher.dispatch(csv_import)

      notice = if result == :deferred
        "再実行を受け付けました。処理中の取り込みが終わると自動で開始します"
      else
        "再実行を開始しました"
      end
      redirect_to csv_import_path(csv_import), notice: notice
    rescue CsvImport::NotRetryableError
      redirect_to csv_import_path(csv_import), alert: "この取り込みは再実行できません"
    rescue CsvImport::FileMissingError
      redirect_to csv_import_path(csv_import), alert: "アップロードしたファイルが残っていません。もう一度アップロードしてください"
    end
  end
end
