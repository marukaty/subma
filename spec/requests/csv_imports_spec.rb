require "rails_helper"

RSpec.describe "CsvImports", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_csv_req", email: "csvreq@example.com") }
  let(:csv_path) { Rails.root.join("spec/fixtures/csv/rakuten_sample_utf8.csv") }

  context "未ログイン時" do
    it "GET /csv_imports は /login にリダイレクト" do
      get csv_imports_path
      expect(response).to redirect_to(login_path)
    end
  end

  context "ログイン済み" do
    before { sign_in_as(user) }

    describe "GET /csv_imports" do
      it "200 OK" do
        get csv_imports_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /csv_imports/new" do
      it "200 OK" do
        get new_csv_import_path
        expect(response).to have_http_status(:ok)
      end

      it "サイズ上限と対応形式を案内する" do
        get new_csv_import_path
        expect(response.body).to include("サイズ上限: 1MB")
        expect(response.body).to include("拡張子 .csv")
      end
    end

    describe "POST /csv_imports" do
      let(:upload) do
        Rack::Test::UploadedFile.new(csv_path, "text/csv")
      end

      def upload_of(content, filename: "statement.csv", content_type: "text/csv")
        Rack::Test::UploadedFile.new(StringIO.new(content.b), content_type, true, original_filename: filename)
      end

      def expect_rejected(params, message)
        expect {
          post csv_imports_path, params: params
        }.not_to change(CsvImport, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(message)
        expect(ProcessCsvJob).not_to have_been_enqueued
      end

      it "CsvImport を作成して ProcessCsvJob を enqueue する" do
        expect {
          post csv_imports_path, params: { csv_import: { format: "rakuten", file: upload } }
        }.to change(CsvImport, :count).by(1)

        ci = CsvImport.last
        expect(ProcessCsvJob).to have_been_enqueued.with(ci.id)
        expect(response).to redirect_to(csv_import_path(ci))
        expect(ci.file).to be_attached
      end

      it "Shift_JIS の CSV（Windows の Excel が付ける Content-Type）も受け付ける" do
        sjis = Rack::Test::UploadedFile.new(
          Rails.root.join("spec/fixtures/csv/rakuten_sample_sjis.csv"), "application/vnd.ms-excel"
        )
        expect {
          post csv_imports_path, params: { csv_import: { format: "rakuten", file: sjis } }
        }.to change(CsvImport, :count).by(1)
        expect(response).to redirect_to(csv_import_path(CsvImport.last))
      end

      it "ファイルなしは 422 で入力画面を再表示する" do
        expect_rejected({ csv_import: { format: "rakuten" } }, "CSV ファイルを選択してください")
      end

      it "csv_import キー自体が無くても 500 にせず 422" do
        expect_rejected({}, "CSV ファイルを選択してください")
      end

      it "file に文字列を送っても 422" do
        expect_rejected({ csv_import: { format: "rakuten", file: "not-a-file" } }, "CSV ファイルを選択してください")
      end

      it "format 未入力は 422" do
        expect_rejected({ csv_import: { format: "", file: upload } }, "フォーマットを選択してください")
      end

      it "format が不正値なら 500 にせず 422" do
        expect_rejected({ csv_import: { format: "bogus", file: upload } }, "対応していないフォーマットです")
      end

      it "enum にあってもアダプタ未実装の format は 422" do
        expect_rejected({ csv_import: { format: "smcc", file: upload } }, "対応していないフォーマットです")
      end

      it "拡張子が .csv 以外は 422" do
        file = upload_of(File.binread(csv_path), filename: "statement.xlsx")
        expect_rejected({ csv_import: { format: "rakuten", file: file } }, "拡張子が .csv のファイルを選択してください")
      end

      it "許可していない Content-Type は 422" do
        file = upload_of(File.binread(csv_path), content_type: "application/pdf")
        expect_rejected({ csv_import: { format: "rakuten", file: file } }, "CSV ファイルとして認識できない形式です")
      end

      it "空のファイルは 422" do
        expect_rejected({ csv_import: { format: "rakuten", file: upload_of("") } }, "ファイルが空です")
      end

      it "既定の上限（1MB）を超えるファイルは 422" do
        big = "日付,内容,金額\n" + ("2026/04/01,NETFLIX.COM,1490\n" * 40_000)
        expect(big.bytesize).to be > 1_048_576
        expect_rejected({ csv_import: { format: "rakuten", file: upload_of(big) } }, "ファイルサイズは 1MB までです")
      end

      it "CSV_MAX_UPLOAD_BYTES で上限を変えられる" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CSV_MAX_UPLOAD_BYTES").and_return("100")
        expect_rejected({ csv_import: { format: "rakuten", file: upload } }, "ファイルサイズは 100B までです")
      end

      describe "行数の上限" do
        def csv_with_rows(count)
          %("利用日","利用店名・商品名","利用金額"\n) +
            Array.new(count) { |i| %("2026/04/01","SHOP #{i}","100"\n) }.join
        end

        it "取引が上限（1,000 行）を超えると 422 でメッセージを出す" do
          expect_rejected({ csv_import: { format: "rakuten", file: upload_of(csv_with_rows(1_001)) } },
                          "取引の行数は 1,000 行までです")
        end

        it "ちょうど上限なら受け付ける" do
          expect {
            post csv_imports_path, params: { csv_import: { format: "rakuten", file: upload_of(csv_with_rows(1_000)) } }
          }.to change(CsvImport, :count).by(1)
          expect(response).to redirect_to(csv_import_path(CsvImport.last))
        end

        it "アップロード画面に行数の上限を案内する" do
          get new_csv_import_path
          expect(response.body).to include("取引の行数は 1,000 行まで")
        end
      end

      it "壊れた CSV（閉じていない引用符）は 422" do
        broken = %("利用日","利用店名・商品名","利用金額"\n"2026/04/01,"NETFLIX.COM",1490\n)
        expect_rejected({ csv_import: { format: "rakuten", file: upload_of(broken) } }, "CSV として読み取れません")
      end

      it "UTF-8 でも Shift_JIS でも読めない文字列は 422" do
        invalid = "\x82\xA0\xFF\xFE,abc\n".b
        expect_rejected({ csv_import: { format: "rakuten", file: upload_of(invalid) } }, "文字コードを読み取れません")
      end

      it "拡張子と Content-Type が CSV でも中身が画像（バイナリ）なら 422" do
        png = "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\rIHDR".b + ("\x00".b * 64)
        expect_rejected({ csv_import: { format: "rakuten", file: upload_of(png) } }, "ファイルの中身が CSV ではありません")
      end

      it "拡張子と Content-Type が CSV でも中身が ZIP（xlsx 等）なら 422" do
        zip = "PK\x03\x04".b + "\x14\x00\x00\x00\x08\x00".b + "[Content_Types].xml".b
        expect_rejected({ csv_import: { format: "rakuten", file: upload_of(zip) } }, "ファイルの中身が CSV ではありません")
      end

      it "許可していないキー（user_id・status・filename 等）は無視する" do
        other = User.create!(firebase_uid: "uid_other_params", email: "op@example.com")
        expect {
          post csv_imports_path, params: {
            csv_import: {
              format: "rakuten", file: upload,
              user_id: other.id, status: "completed", filename: "../../etc/passwd.csv"
            }
          }
        }.to change(CsvImport, :count).by(1)

        ci = CsvImport.last
        expect(ci.user).to eq(user)
        expect(ci.status).to eq("uploading")
        expect(ci.filename).to eq("rakuten_sample_utf8.csv")
        expect(response).to redirect_to(csv_import_path(ci))
      end

      it "長いファイル名は拡張子を残して 100 文字に切って保存する" do
        file = upload_of(File.binread(csv_path), filename: "#{'a' * 300}.csv")
        post csv_imports_path, params: { csv_import: { format: "rakuten", file: file } }

        ci = CsvImport.last
        expect(response).to redirect_to(csv_import_path(ci))
        expect(ci.filename.length).to eq(100)
        expect(ci.filename).to end_with(".csv")
        expect(ci.file.filename.to_s).to eq(ci.filename)
      end
    end

    describe "GET /csv_imports/:id" do
      it "200 OK & 自分のレコードを表示" do
        ci = current_user_csv_import
        get csv_import_path(ci)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(ci.filename)
      end

      it "集計の「サブスク判定」は一覧の件数と一致し、内訳とスキップ件数を表示する" do
        ci = user.csv_imports.create!(filename: "done.csv", format: :rakuten, status: :completed,
                                      original_row_count: 6, matched_count: 2, skipped_duplicate_count: 1)
        { "subscription" => 2, "non_subscription" => 2, "unknown" => 1 }.each do |classification, n|
          n.times do |i|
            ci.transactions.create!(user: user, transaction_date: Date.new(2026, 4, i + 1), amount: 100,
                                    description: "#{classification} #{i}", classification: classification)
          end
        end

        get csv_import_path(ci)

        body = response.body
        expect(body).to include("サブスク判定（2 件）")
        expect(body).to match(%r{6 件 /\s*<span class="text-blue-600">2 件</span>})
        breakdown = Nokogiri::HTML(body).at_css('[data-testid="csv-import-breakdown"]').text.squish
        expect(breakdown).to eq("サブスク候補 2 ・ サブスクではない 2 ・ 未判定 1 ・ スキップ 1")
        expect(body).to include("既に取り込み済みの取引 1 件はスキップしました")
      end

      it "AI 判定の上限で送らなかった行があれば、未判定の理由を表示する" do
        ci = user.csv_imports.create!(filename: "limited.csv", format: :rakuten, status: :completed,
                                      original_row_count: 3, matched_count: 0, ai_skipped_count: 2)
        get csv_import_path(ci)
        message = Nokogiri::HTML(response.body).at_css('[data-testid="csv-import-ai-skipped"]').text.squish
        expect(message).to include("AI 判定の上限に達したため 2 行は未判定です")
      end

      it "AI 判定の上限に達していなければ、上限の案内は出さない" do
        ci = user.csv_imports.create!(filename: "ok.csv", format: :rakuten, status: :completed,
                                      original_row_count: 3, matched_count: 0)
        get csv_import_path(ci)
        expect(response.body).not_to include("AI 判定の上限")
      end

      it "すべてスキップされたときは、取り込み済みである旨を表示する" do
        ci = user.csv_imports.create!(filename: "again.csv", format: :rakuten, status: :completed,
                                      original_row_count: 5, matched_count: 0, skipped_duplicate_count: 5)
        get csv_import_path(ci)
        expect(response.body).to include("新しい取引はありませんでした（すべて取り込み済みです）")
      end

      it "他ユーザーのレコードは 404" do
        other = User.create!(firebase_uid: "uid_other_csv", email: "o@example.com")
        ci = other.csv_imports.create!(filename: "x.csv", format: :rakuten, status: :uploading)
        get csv_import_path(ci)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST /csv_imports/:id/register" do
      let(:csv_import) { user.csv_imports.create!(filename: "x.csv", format: :rakuten, status: :completed) }
      let!(:tx_sub) do
        csv_import.transactions.create!(
          user: user, transaction_date: Date.new(2026, 4, 1),
          amount: 1490, description: "NETFLIX.COM",
          classification: :subscription, classifier: :rule, confidence: 1.0,
          inferred_service_name: "Netflix", inferred_category: "エンタメ"
        )
      end

      it "チェックされた行をサブスクとして一括登録する" do
        expect {
          post register_csv_import_path(csv_import), params: {
            selections: {
              tx_sub.id.to_s => { include: "1", service_name: "Netflix", category: "エンタメ", amount: "1490" }
            }
          }
        }.to change(Subscription, :count).by(1)

        sub = Subscription.last
        expect(sub.service_name).to eq("Netflix")
        expect(sub.category).to eq("エンタメ")
        expect(sub.amount).to eq(1490)
        expect(sub.source).to eq("csv")
        expect(sub.user).to eq(user)
        expect(tx_sub.reload.matched_subscription).to eq(sub)
        expect(response).to redirect_to(subscriptions_path)
      end

      it "チェック無しの行は登録されない" do
        expect {
          post register_csv_import_path(csv_import), params: {
            selections: {
              tx_sub.id.to_s => { include: "0", service_name: "Netflix", category: "エンタメ", amount: "1490" }
            }
          }
        }.not_to change(Subscription, :count)
      end

      it "AI 判定の取引は source: ai で登録される" do
        ai_tx = csv_import.transactions.create!(
          user: user, transaction_date: Date.new(2026, 4, 3),
          amount: 2000, description: "MYSTERY SUBSCRIPTION",
          classification: :subscription, classifier: :ai, confidence: 0.9,
          inferred_service_name: "Mystery", inferred_category: "その他"
        )
        post register_csv_import_path(csv_import), params: {
          selections: {
            ai_tx.id.to_s => { include: "1", service_name: "Mystery", category: "その他", amount: "2000" }
          }
        }
        expect(Subscription.last.source).to eq("ai")
      end

      it "他ユーザーの csv_import に対しては 404" do
        other = User.create!(firebase_uid: "uid_other_register", email: "o2@example.com")
        other_ci = other.csv_imports.create!(filename: "y.csv", format: :rakuten, status: :completed)
        post register_csv_import_path(other_ci), params: { selections: {} }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  def current_user_csv_import
    user.csv_imports.create!(filename: "test.csv", format: :rakuten, status: :uploading)
  end
end
