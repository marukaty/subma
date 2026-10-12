# 再取り込みで二重に保存されてしまった取引を掃除する（ADR-0007「再取り込みの重複」）。
# 運用者が rake（transactions:dedup）から手動で実行する。
#
# 判定は ProcessCsvJob の重複スキップと同じ:
#   - 同じユーザーの「取引日・利用店名・金額」（Transaction.dedup_key）が一致するものを同じ取引とみなす
#   - 取り込みの古い順に見て、それまでの取り込みで保存済みの件数を超えた分だけを残す
#     （同じ CSV 内の正当な複数件は残り、別の取り込みで重ねて保存された分だけが削除候補になる）
#   - 同じ取り込みの中では id の小さい（先に保存された）行を残す
#
# [ai-assisted]
class TransactionDeduplicator
  # transaction: 削除候補、kept_id: 残す側の同じ取引の id（同じ取り込み内で残るものがあればその id）
  Duplicate = Struct.new(:transaction, :kept_id, keyword_init: true)

  def initialize(user)
    @user = user
  end

  # @return [Array<Duplicate>] 削除候補（何も変更しない）
  def duplicates
    saved_counts = Hash.new(0)
    first_kept_ids = {}
    transactions_by_import = Transaction.where(user_id: @user.id).order(:id).group_by(&:csv_import_id)

    import_ids_in_order.each_with_object([]) do |import_id, result|
      transactions_by_import.fetch(import_id, []).group_by(&:dedup_key).each do |key, group|
        keep_count = [ group.size - saved_counts[key], 0 ].max
        kept, dropped = group.take(keep_count), group.drop(keep_count)

        first_kept_ids[key] ||= kept.first&.id
        saved_counts[key] += keep_count
        dropped.each { |tx| result << Duplicate.new(transaction: tx, kept_id: first_kept_ids[key]) }
      end
    end
  end

  # 削除候補を消し、影響のあった取り込みの件数（matched_count / skipped_duplicate_count）を直す。
  # @return [Array<Duplicate>] 削除したもの
  def delete_duplicates!
    found = duplicates
    return found if found.empty?

    deleted_counts = found.map { |dup| dup.transaction.csv_import_id }.tally
    Transaction.transaction do
      Transaction.where(id: found.map { |dup| dup.transaction.id }).delete_all
      CsvImport.where(id: deleted_counts.keys).find_each do |csv_import|
        csv_import.update_columns(
          matched_count: csv_import.transactions.classification_subscription.count,
          skipped_duplicate_count: csv_import.skipped_duplicate_count + deleted_counts[csv_import.id],
          updated_at: Time.current
        )
      end
    end
    found
  end

  private

  def import_ids_in_order
    CsvImport.where(user_id: @user.id).order(:created_at, :id).pluck(:id)
  end
end
