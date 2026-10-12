# 監査ログ（NFR-S-05）
# 全書き込み系操作（POST / PUT / PATCH / DELETE）と認証イベントを記録する
#
# 設計判断:
# - user は null 許容（認証前イベントを記録するため）
# - resource_type / resource_id は任意（特定リソースを操作した場合のみ）
# - ip_address / user_agent は HTTP リクエストから取得
class AuditLog < ApplicationRecord
  belongs_to :user, optional: true

  validates :action, presence: true

  # 認証関連イベント
  ACTION_AUTH_SIGN_IN = "auth.sign_in".freeze
  ACTION_AUTH_SIGN_IN_FAILED = "auth.sign_in_failed".freeze
  ACTION_AUTH_SIGN_OUT = "auth.sign_out".freeze
  # 許可リスト（ADR-0006）: ログイン拒否と、ログイン中の締め出し
  # 拒否された人は User を作らないので user は nil。メールアドレスは監査ログに保存しない
  ACTION_AUTH_SIGN_IN_DENIED = "auth.sign_in_denied".freeze
  ACTION_AUTH_SESSION_REVOKED = "auth.session_revoked".freeze

  # 退会（アカウントと全データの削除）
  # - delete_requested: 削除の依頼を受けた。確認が一致せず削除しなかった場合も記録する
  # - deleted: 削除が完了した。user は nil（ユーザーはもう存在しない）
  # 削除が完了したら、この 2 件以外のそのユーザーの監査ログは消し、delete_requested も user_id を null にする
  # メールアドレスは記録しない
  ACTION_ACCOUNT_DELETE_REQUESTED = "account.delete_requested".freeze
  ACTION_ACCOUNT_DELETED = "account.deleted".freeze
end
