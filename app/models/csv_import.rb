class CsvImport < ApplicationRecord
  belongs_to :user
  has_many :transactions, dependent: :destroy
  # アップロードされた CSV ファイル本体（処理が completed になったら削除する: NFR-S-09 / ADR-0007）
  has_one_attached :file

  enum :format, {
    rakuten: 0,
    smcc: 1,    # 三井住友
    jcb: 2,
    aeon: 3,
    mufg: 4,
    generic: 5
  }, prefix: true

  enum :status, {
    uploading: 0,
    processing: 1,
    rule_matching: 2,
    ai_analyzing: 3,
    completed: 4,
    failed: 5
  }, prefix: true

  # ProcessCsvJob が処理権を取ってから終わるまでの状態
  IN_PROGRESS_STATUSES = %w[processing rule_matching ai_analyzing].freeze

  # 処理中のまま更新が止まっているとみなすまでの時間。
  # Cloud Run のリクエストタイムアウト（900 秒）の 2 倍にして、正常に動いている処理を誤判定しない。
  STALE_AFTER = 30.minutes

  class NotRetryableError < StandardError; end
  class FileMissingError < StandardError; end

  validates :filename, presence: true, length: { maximum: 255 }
  validates :format, presence: true
  validates :status, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :in_progress, -> { where(status: IN_PROGRESS_STATUSES) }
  # 実際に処理が動いているとみなせるもの（止まったまま放置されたものは含めない）
  scope :actively_processing, -> { in_progress.where(updated_at: STALE_AFTER.ago..) }

  def in_progress?
    IN_PROGRESS_STATUSES.include?(status)
  end

  # 処理中のまま STALE_AFTER 以上更新がない（インスタンスの停止などで処理が途中で止まった）
  def stale?
    in_progress? && updated_at < STALE_AFTER.ago
  end

  # 再処理できるのは、失敗したものと、処理中のまま止まったものだけ
  def retryable?
    status_failed? || stale?
  end

  # 再処理のために uploading（未処理）に戻す。キューへの登録は呼び出し側が
  # CsvProcessingDispatcher.dispatch で行う。
  def reset_for_retry!
    with_lock do
      raise NotRetryableError, "status is #{status}" unless retryable?
      raise FileMissingError, "uploaded file is already gone" unless file.attached?

      update!(status: :uploading, error_summary: nil)
    end
  end

  # 抽出が終わって CSV 本体は不要になった、という意味でファイル削除を行う
  # ProcessCsvJob が completed にしたときだけ呼ぶ（失敗時は再処理のために残す: ADR-0007）
  def purge_uploaded_file!
    file.purge if file.attached?
  end
end
