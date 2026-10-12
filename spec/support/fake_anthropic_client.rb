# Claude API の代わりに使うクライアント（実 HTTP は送らない）。
# messages.create に渡された取引（JSON）を記録し、すべての id に「サブスクではない」を返す。
# subscriptions に店名を入れると、その店名の行だけ「サブスク」と返す。
class FakeAnthropicClient
  TextBlock = Struct.new(:type, :text)
  Message = Struct.new(:content)

  attr_reader :requests

  def initialize(subscriptions: [])
    @subscriptions = subscriptions
    @requests = []
  end

  def messages
    self
  end

  def create(**kwargs)
    payload = JSON.parse(kwargs[:messages].first[:content].split("\n\n", 2).last)
    @requests << payload
    results = payload.map do |row|
      subscription = @subscriptions.include?(row["description"])
      { id: row["id"], is_subscription: subscription, confidence: 0.9,
        service_name: subscription ? row["description"] : nil, category: nil }
    end
    Message.new([ TextBlock.new(:text, JSON.generate(results: results)) ])
  end

  # 送られた取引（全リクエスト分）
  def sent_rows
    @requests.flatten(1)
  end
end
