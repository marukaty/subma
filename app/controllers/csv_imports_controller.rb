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

  # 抽出結果レビューでチェックされた取引を Subscription レコードに一括登録する
  # POST /csv_imports/:id/register
  # params[:selections] = { "<transaction_id>" => { include: "1", service_name: "...", category: "...", amount: "..." } }
  def register
    @csv_import = current_user.csv_imports.find(params[:id])
    @audit_resource = @csv_import

    selections = params[:selections] || {}
    created_count = 0

    Subscription.transaction do
      selections.each do |transaction_id, attrs|
        next unless attrs[:include] == "1"

        tx = @csv_import.transactions.find_by(id: transaction_id)
        next unless tx

        sub = current_user.subscriptions.create!(
          service_name: attrs[:service_name].presence || tx.description,
          amount: attrs[:amount].presence || tx.amount,
          currency: "JPY",
          billing_cycle: :monthly, # MVP: monthly 固定。将来的にレビュー時に選択可
          status: :active,
          source: tx.classifier == "ai" ? :ai : :csv,
          category: attrs[:category].presence,
          started_at: tx.transaction_date,
          next_billing_date: tx.transaction_date + 1.month,
          memo: "CSV取り込み (##{@csv_import.id}) より自動登録"
        )
        tx.update!(matched_subscription: sub, classifier: :user)
        created_count += 1
      end
    end

    redirect_to subscriptions_path,
                notice: "#{created_count} 件のサブスクを登録しました"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to csv_import_path(@csv_import),
                alert: "登録に失敗しました: #{e.message}"
  end
end
