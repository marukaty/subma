require "csv"

# CSV アップロードの入力検証（POST /csv_imports）。
#
# ファイル本体は信頼できない入力として扱い、保存（attach）やジョブ投入の前に
# ここで形式・サイズ・中身を確認する。検証ルールを足すときは validate を追加する
# （例: 行数の上限は全行を読む別の検証として追加できる）。
class CsvUploadForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  DEFAULT_MAX_BYTES = 1_048_576 # 1MB。環境変数 CSV_MAX_UPLOAD_BYTES で変更可
  ALLOWED_EXTENSIONS = %w[.csv].freeze
  # Windows で Excel が入っていると .csv は application/vnd.ms-excel として送られる
  ALLOWED_CONTENT_TYPES = %w[text/csv text/plain application/vnd.ms-excel].freeze
  # 中身から判定した種類（マジックナンバー）がこれ以外なら CSV ではないとみなす
  ALLOWED_DETECTED_TYPES = %w[application/octet-stream text/plain text/csv].freeze
  HEAD_BYTES = 16.kilobytes # 先頭だけ読んで CSV として解釈できるかを見る
  PREVIEW_ROWS = 5
  MAX_FILENAME_LENGTH = 100

  attribute :file
  attribute :format, :string

  validate :file_must_be_uploaded
  validate :file_attributes_must_be_valid, if: :uploaded_file?
  validates :format, presence: true
  validates :format, inclusion: { in: ->(_) { supported_formats }, message: :unsupported_format },
                     allow_blank: true

  # CsvImport の enum にあり、かつパーサのアダプタが実装済みの format だけを受け付ける
  def self.supported_formats
    CsvImport.formats.keys & Csv::Parser::ADAPTERS.keys
  end

  def self.max_bytes
    value = ENV["CSV_MAX_UPLOAD_BYTES"].to_s.strip
    return DEFAULT_MAX_BYTES if value.empty?

    bytes = Integer(value, 10)
    bytes.positive? ? bytes : DEFAULT_MAX_BYTES
  rescue ArgumentError
    DEFAULT_MAX_BYTES
  end

  # 画面表示用（例: "1MB"、"512KB"）
  def self.max_size_label
    bytes = max_bytes
    if (bytes % 1.megabyte).zero?
      "#{bytes / 1.megabyte}MB"
    elsif bytes >= 1.kilobyte
      "#{(bytes / 1.kilobyte.to_f).round(1).to_s.delete_suffix('.0')}KB"
    else
      "#{bytes}B"
    end
  end

  # 保存用のファイル名。パス部分を除き、拡張子を残して MAX_FILENAME_LENGTH 文字に切る
  def sanitized_filename
    name = File.basename(file.original_filename.to_s.tr("\\", "/"))
    return name if name.length <= MAX_FILENAME_LENGTH

    ext = File.extname(name)
    name[0, MAX_FILENAME_LENGTH - ext.length] + ext
  end

  # Active Storage に渡す内容。blob のファイル名も切り詰めたものにする（列の長さを超えないように）
  def attachable
    { io: upload_io, filename: sanitized_filename, content_type: normalized_content_type }
  end

  private

  def upload_io
    file.respond_to?(:tempfile) ? file.tempfile : file
  end

  def normalized_content_type
    file.content_type.to_s.split(";").first.to_s.strip.downcase
  end

  def uploaded_file?
    file.respond_to?(:original_filename) && file.respond_to?(:read) && file.respond_to?(:size)
  end

  def file_must_be_uploaded
    errors.add(:file, :blank) unless uploaded_file?
  end

  # 1 つ目に見つかった問題だけを返す（中身の検証は、拡張子・種類・サイズが正しいときだけ行う）
  def file_attributes_must_be_valid
    error = extension_error || content_type_error || size_error || content_error
    return unless error

    options = error == :too_large ? { max_size: self.class.max_size_label } : {}
    errors.add(:file, error, **options)
  end

  def extension_error
    ext = File.extname(file.original_filename.to_s).downcase
    :invalid_extension unless ALLOWED_EXTENSIONS.include?(ext)
  end

  def content_type_error
    :invalid_content_type unless ALLOWED_CONTENT_TYPES.include?(normalized_content_type)
  end

  def size_error
    return :empty if file.size.to_i.zero?

    :too_large if file.size > self.class.max_bytes
  end

  def content_error
    head = read_head
    return :not_csv if binary?(head)

    text = decode(head)
    return :invalid_encoding unless text

    rows = parse_preview(text)
    :malformed_csv if rows.blank?
  rescue CSV::MalformedCSVError
    :malformed_csv
  end

  def read_head
    io = upload_io
    io.rewind
    head = io.read(HEAD_BYTES + 1).to_s.b
    io.rewind
    return head if head.bytesize <= HEAD_BYTES

    # 途中で切れた行（マルチバイト文字の途中で切れることもある）を捨てる
    head = head.byteslice(0, HEAD_BYTES)
    last_newline = head.rindex("\n")
    last_newline ? head.byteslice(0, last_newline + 1) : head
  end

  def binary?(bytes)
    return true if bytes.include?("\x00".b)

    detected = Marcel::MimeType.for(StringIO.new(bytes))
    !ALLOWED_DETECTED_TYPES.include?(detected)
  end

  # Csv::Adapters::BaseAdapter と同じく UTF-8 を優先し、だめなら Shift_JIS 系として読む。
  # 検証では Shift_JIS の上位互換である Windows-31J（機種依存文字を含む）で正しく読めることを確認する
  def decode(bytes)
    utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
    return utf8.delete_prefix("﻿") if utf8.valid_encoding?

    sjis = bytes.dup.force_encoding(Encoding::Windows_31J)
    sjis.valid_encoding? ? sjis.encode(Encoding::UTF_8) : nil
  end

  def parse_preview(text)
    csv = CSV.new(text)
    rows = []
    PREVIEW_ROWS.times do
      row = csv.shift
      break if row.nil?

      rows << row
    end
    rows.reject { |row| row.compact.empty? }
  end
end
