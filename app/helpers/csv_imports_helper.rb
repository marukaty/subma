module CsvImportsHelper
  def t_csv_status(key)
    {
      "uploading"     => "アップロード中",
      "processing"    => "処理開始",
      "rule_matching" => "規則ベース判定中",
      "ai_analyzing"  => "AI判定中",
      "completed"     => "完了",
      "failed"        => "失敗"
    }[key.to_s] || key.to_s
  end

  def csv_status_badge_class(status)
    case status.to_s
    when "completed" then "bg-green-100 text-green-700"
    when "failed"    then "bg-red-100 text-red-600"
    when "uploading", "processing", "rule_matching", "ai_analyzing"
      "bg-blue-100 text-blue-700"
    else "bg-gray-100 text-gray-700"
    end
  end

  def t_csv_classification(key)
    {
      "subscription"     => "サブスク",
      "non_subscription" => "サブスクではない",
      "unknown"          => "未判定"
    }[key.to_s] || key.to_s
  end
end
