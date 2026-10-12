# 取引データの運用タスク（ADR-0007「再取り込みの重複」）
namespace :transactions do
  desc "再取り込みで二重に保存された取引を削除する: bin/rails 'transactions:dedup[USER_ID]'" \
       "（削除せずに候補だけ表示: 'transactions:dedup[USER_ID,dry_run]' または DRY_RUN=1）"
  task :dedup, [ :user_id, :mode ] => :environment do |_t, args|
    usage = "usage: bin/rails 'transactions:dedup[USER_ID]' / 'transactions:dedup[USER_ID,dry_run]' / DRY_RUN=1"
    abort usage if args[:user_id].blank?
    abort usage if args[:mode].present? && args[:mode] != "dry_run"

    user = User.find_by(id: args[:user_id])
    abort "user_id=#{args[:user_id]} not found" if user.nil?

    dry_run = args[:mode] == "dry_run" || ENV["DRY_RUN"] == "1"
    deduplicator = TransactionDeduplicator.new(user)
    found = dry_run ? deduplicator.duplicates : deduplicator.delete_duplicates!

    # ログに残るので、利用店名・金額は出さない（id と日付だけ）
    found.each do |dup|
      tx = dup.transaction
      line = "transaction_id=#{tx.id} csv_import_id=#{tx.csv_import_id} date=#{tx.transaction_date} " \
             "duplicate_of=#{dup.kept_id || '-'}"
      line += " matched_subscription_id=#{tx.matched_subscription_id}" if tx.matched_subscription_id
      puts line
    end

    verb = dry_run ? "would delete" : "deleted"
    puts "user_id=#{user.id} #{verb} #{found.size} duplicate transaction(s)#{' (dry run)' if dry_run}"
  end
end
