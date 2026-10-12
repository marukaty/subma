# CSV 取り込みの運用タスク（ADR-0007）
namespace :csv_imports do
  desc "失敗した（または処理中のまま止まった）CSV 取り込みを再処理する: bin/rails 'csv_imports:retry[ID]'"
  task :retry, [ :id ] => :environment do |_t, args|
    abort "usage: bin/rails 'csv_imports:retry[ID]'" if args[:id].blank?

    csv_import = CsvImport.find(args[:id])
    csv_import.reset_for_retry!
    result = CsvProcessingDispatcher.dispatch(csv_import)
    puts "csv_import_id=#{csv_import.id} reset to uploading (#{result})"
  rescue ActiveRecord::RecordNotFound, CsvImport::NotRetryableError, CsvImport::FileMissingError => e
    abort "csv_import_id=#{args[:id]} cannot be retried: #{e.message}"
  end
end
