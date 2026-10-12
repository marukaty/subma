class CsvImportsController < ApplicationController
  before_action :authenticate_user!

  # 入力検証のエラーメッセージ（config/locales/ja.yml）を日本語で出す
  around_action :use_japanese_locale, only: %i[new create]

  def index
    @csv_imports = current_user.csv_imports.recent.limit(50)
  end

  def new
    @upload = CsvUploadForm.new(format: CsvUploadForm.supported_formats.first)
    @csv_import = build_form_model(@upload)
  end

  def create
    @upload = CsvUploadForm.new(upload_params)

    unless @upload.valid?
      @csv_import = build_form_model(@upload)
      render :new, status: :unprocessable_content
      return
    end

    csv_import = current_user.csv_imports.create!(
      filename: @upload.sanitized_filename,
      format: @upload.format,
      status: :uploading
    )
    csv_import.file.attach(@upload.attachable)
    @audit_resource = csv_import

    # Phase 4: 直接 ProcessCsvJob.perform_later を呼ばず、ディスパッチャ経由にする
    # （dev/test=Sidekiq、production=Cloud Tasks）
    CsvProcessingDispatcher.dispatch(csv_import)

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

  private

  # csv_import キーが無い・形が違うときも 400 / 500 にせず、空の入力として検証に回す
  def upload_params
    params.expect(csv_import: [ :file, :format ])
  rescue ActionController::ParameterMissing
    {}
  end

  # フォームの name 属性（csv_import[...]）を保つための入れ物。保存はしない
  def build_form_model(upload)
    format = CsvUploadForm.supported_formats.include?(upload.format) ? upload.format : CsvUploadForm.supported_formats.first
    current_user.csv_imports.new(format: format, status: :uploading)
  end

  def use_japanese_locale(&)
    I18n.with_locale(:ja, &)
  end
end
