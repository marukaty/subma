module SubscriptionsHelper
  def t_billing_cycle(key)
    {
      "monthly" => "月額",
      "yearly"  => "年額",
      "weekly"  => "週額",
      "custom"  => "カスタム"
    }[key.to_s] || key.to_s
  end

  def t_status(key)
    {
      "active"    => "利用中",
      "paused"    => "一時停止",
      "cancelled" => "解約済み"
    }[key.to_s] || key.to_s
  end

  def status_badge_class(status)
    case status.to_s
    when "active"    then "bg-green-100 text-green-700"
    when "paused"    then "bg-yellow-100 text-yellow-700"
    when "cancelled" then "bg-gray-100 text-gray-500"
    else "bg-gray-100 text-gray-700"
    end
  end
end
