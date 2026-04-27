class CsvImport < ApplicationRecord
  belongs_to :user
  has_many :transactions, dependent: :destroy
  # アップロードされた CSV ファイル本体（処理後即削除する: NFR-S-09）
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

  validates :filename, presence: true, length: { maximum: 255 }
  validates :format, presence: true
  validates :status, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # 抽出が終わって CSV 本体は不要になった、という意味でファイル削除を行う
  # ProcessCsvJob の最後に呼ぶ想定（NFR-S-09）
  def purge_uploaded_file!
    file.purge if file.attached?
  end
end
