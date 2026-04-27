class CsvImportsController < ApplicationController
  before_action :authenticate_user!

  MAX_UPLOAD_SIZE = 5.megabytes  # 要件 §3.1 F-04

  def index
    @csv_imports = current_user.csv_imports.recent.limit(50)
  end

  def new
    @csv_import = current_user.csv_imports.new(format: :rakuten, status: :uploading)
  end

  def create
    file = params[:csv_import][:file]
    format = params[:csv_import][:format].presence || "rakuten"

    if file.blank?
      redirect_to new_csv_import_path, alert: "CSV ファイルを選択してください"
      return
    end

    if file.size > MAX_UPLOAD_SIZE
      redirect_to new_csv_import_path, alert: "ファイルサイズは 5MB まで対応しています"
      return
    end

    csv_import = current_user.csv_imports.create!(
      filename: file.original_filename,
      format: format,
      status: :uploading
    )
    csv_import.file.attach(file)
    @audit_resource = csv_import

    ProcessCsvJob.perform_later(csv_import.id)

    redirect_to csv_import_path(csv_import), notice: "アップロードしました。AI が抽出中です..."
  end

  def show
    @csv_import = current_user.csv_imports.find(params[:id])
    @transactions = @csv_import.transactions.order(:transaction_date, :description)
  end
end
