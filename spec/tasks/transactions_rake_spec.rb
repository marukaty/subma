require "rails_helper"
require "rake"

RSpec.describe "transactions:dedup", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("transactions:dedup")
  end

  let(:task) { Rake::Task["transactions:dedup"] }
  let(:user) { User.create!(firebase_uid: "uid_dedup_task", email: "dedup-task@example.com") }
  let(:other_user) { User.create!(firebase_uid: "uid_dedup_task_other", email: "dedup-task-other@example.com") }

  def create_import(owner, created_at:)
    CsvImport.create!(user: owner, filename: "x.csv", format: :rakuten, status: :completed, created_at: created_at)
  end

  def add_tx(csv_import, date:, description:, amount:, classification: :unknown)
    csv_import.transactions.create!(user: csv_import.user, transaction_date: date, description: description,
                                    amount: amount, classification: classification)
  end

  def run_task(*args)
    task.reenable
    expect { task.invoke(*args) }.to output.to_stdout
  end

  let!(:first) { create_import(user, created_at: 2.days.ago) }
  let!(:second) { create_import(user, created_at: 1.day.ago) }

  # first: 同じ CSV 内の正当な 2 件（CAFE）+ NETFLIX
  # second: first と同じ内容をもう一度取り込んだもの + 新しい取引 1 件
  let!(:first_cafe) do
    2.times.map { add_tx(first, date: Date.new(2026, 4, 20), description: "SAMPLE CAFE", amount: 500) }
  end
  let!(:first_netflix) do
    add_tx(first, date: Date.new(2026, 4, 1), description: "NETFLIX.COM", amount: 1490, classification: :subscription)
  end
  let!(:second_dups) do
    [
      add_tx(second, date: Date.new(2026, 4, 20), description: "SAMPLE CAFE", amount: 500),
      add_tx(second, date: Date.new(2026, 4, 20), description: "SAMPLE CAFE", amount: 500),
      add_tx(second, date: Date.new(2026, 4, 1), description: "NETFLIX.COM", amount: 1490, classification: :subscription)
    ]
  end
  let!(:second_new) { add_tx(second, date: Date.new(2026, 5, 1), description: "NEW SHOP", amount: 300) }

  # 他ユーザーの同じ二重登録（触れてはいけない）
  let!(:others) do
    a = create_import(other_user, created_at: 2.days.ago)
    b = create_import(other_user, created_at: 1.day.ago)
    [ add_tx(a, date: Date.new(2026, 4, 1), description: "NETFLIX.COM", amount: 1490),
      add_tx(b, date: Date.new(2026, 4, 1), description: "NETFLIX.COM", amount: 1490) ]
  end

  it "dry_run では削除候補を表示し、何も削除しない" do
    second.update_columns(matched_count: 1)

    expect {
      task.reenable
      expect { task.invoke(user.id.to_s, "dry_run") }
        .to output(/would delete 3 duplicate transaction\(s\) \(dry run\)/).to_stdout
    }.not_to change(Transaction, :count)
    expect(second.reload.matched_count).to eq(1)
  end

  it "DRY_RUN=1 でも削除しない" do
    ENV["DRY_RUN"] = "1"
    expect { run_task(user.id.to_s) }.not_to change(Transaction, :count)
  ensure
    ENV.delete("DRY_RUN")
  end

  it "実行すると、新しい取り込み側の重複だけを削除し、件数を直す" do
    second.update_columns(matched_count: 1, skipped_duplicate_count: 0)

    run_task(user.id.to_s)

    expect(Transaction.where(id: second_dups.map(&:id))).to be_empty
    expect(first.transactions.count).to eq(3)          # 同じ CSV 内の正当な 2 件も残る
    expect(second.transactions).to contain_exactly(second_new)
    second.reload
    expect(second.matched_count).to eq(0)
    expect(second.skipped_duplicate_count).to eq(3)
  end

  it "他のユーザーの取引には触れない" do
    run_task(user.id.to_s)
    expect(Transaction.where(id: others.map(&:id)).count).to eq(2)
  end

  it "2 回実行しても 2 回目は何も削除しない" do
    run_task(user.id.to_s)
    expect { run_task(user.id.to_s) }.not_to change(Transaction, :count)
  end

  it "ログに利用店名・金額を出さない" do
    task.reenable
    expect { task.invoke(user.id.to_s, "dry_run") }.not_to output(/SAMPLE CAFE|NETFLIX|1490/).to_stdout
  end
end
