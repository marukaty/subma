# 退会: ユーザー本人のアカウントと、そのユーザーに紐づくデータをすべて削除する。
#
# 削除の順序（外部キーの向きに合わせ、子から親へ）:
#   1. transactions（取り込んだ明細）
#   2. csv_imports の添付ファイルの紐付け（active_storage_attachments）
#   3. csv_imports
#   4. subscriptions
#   5. audit_logs（このユーザーの操作履歴）。ただし今回の削除依頼（account.delete_requested）だけは
#      user_id を null にして残す
#   6. users
#   7. account.deleted を user_id なしで記録する
# 1〜7 は 1 つの DB トランザクションで行い、途中で失敗したら何も消えない。
#
# 添付ファイル本体（Active Storage の blob とストレージ上のファイル）は、ロールバックで元に戻せないため
# トランザクションのコミット後に同期で purge する。purge に失敗しても DB 側の削除は完了しており、
# ファイルはどのユーザーからも参照されない（本番のバケットはライフサイクル設定で 1 日後に消える: ADR-0005）。
#
# Firebase Authentication 側のアカウントは削除しない（Google アカウント自体は利用者本人のもの）。
# 再ログインすると、許可リストに入っている限り新しいユーザーとして作られる。
#
# 監査ログにはメールアドレスを保存しない（ADR-0006 と同じ方針）。
class AccountDeletion
  def initialize(user:, request_log: nil, ip_address: nil, user_agent: nil)
    @user = user
    @request_log = request_log
    @ip_address = ip_address
    @user_agent = user_agent.to_s.first(500)
  end

  # @return [AuditLog] 記録した account.deleted のログ
  def call
    blob_ids = []
    deleted_log = nil

    ActiveRecord::Base.transaction do
      # 取り込みジョブ（ProcessCsvJob）も同じ行をロックしてから書き込むので、処理中の取り込みとは直列になる
      @user.lock!

      csv_import_ids = CsvImport.where(user_id: @user.id).pluck(:id)
      attachments = ActiveStorage::Attachment.where(record_type: CsvImport.name, record_id: csv_import_ids)
      blob_ids = attachments.pluck(:blob_id)

      Transaction.where(user_id: @user.id).or(Transaction.where(csv_import_id: csv_import_ids)).delete_all
      attachments.delete_all
      CsvImport.where(id: csv_import_ids).delete_all
      Subscription.where(user_id: @user.id).delete_all

      kept_log_ids = [ @request_log&.id ].compact
      AuditLog.where(user_id: @user.id).where.not(id: kept_log_ids).delete_all
      AuditLog.where(id: kept_log_ids).update_all(user_id: nil)

      @user.reload.destroy!

      deleted_log = AuditLog.create!(
        user: nil,
        action: AuditLog::ACTION_ACCOUNT_DELETED,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    purge_blobs(blob_ids)
    deleted_log
  end

  private

  def purge_blobs(blob_ids)
    ActiveStorage::Blob.where(id: blob_ids).find_each do |blob|
      blob.purge
    rescue StandardError => e
      Rails.logger.error("[account_deletion] failed to purge blob id=#{blob.id}: #{e.class}: #{e.message}")
    end
  end
end
