require "rails_helper"

RSpec.describe Classifiers::AiClassifier do
  # Anthropic クライアントを模した Double。
  # 実 HTTP は叩かず、messages.create がテストごとに用意した応答を返す。
  let(:messages_resource) { instance_double("Anthropic::Resources::Messages") }
  let(:fake_client) { instance_double("Anthropic::Client", messages: messages_resource) }
  let(:classifier) { described_class.new(client: fake_client) }

  # Anthropic SDK の Message オブジェクトを模した Struct。
  # text_block.type は Symbol(:text)、text_block.text は文字列。
  let(:text_block_class) { Struct.new(:type, :text) }
  let(:message_class)    { Struct.new(:content) }

  def fake_message(text)
    message_class.new([ text_block_class.new(:text, text) ])
  end

  describe "#classify" do
    let(:rows) do
      [
        { date: Date.new(2026, 4, 1), description: "NETFLIX.COM 1234567890", amount: BigDecimal("1490") },
        { date: Date.new(2026, 4, 5), description: "ENEOS XXX",                 amount: BigDecimal("5500") }
      ]
    end

    context "API が両方のエントリに対して結果を返した場合" do
      before do
        ai_response = fake_message(JSON.generate(
          results: [
            { id: 0, is_subscription: true,  confidence: 0.95, service_name: "Netflix", category: "エンタメ" },
            { id: 1, is_subscription: false, confidence: 0.9,  service_name: nil,       category: nil }
          ]
        ))
        allow(messages_resource).to receive(:create).and_return(ai_response)
      end

      it "subscription 判定は classified、non_subscription も classified（unknown 以外は全て classified）" do
        result = classifier.classify(rows)
        expect(result.classified.size).to eq(2)
        expect(result.unclassified).to be_empty
      end

      it "subscription 行に AI 情報が付与される" do
        result = classifier.classify(rows)
        netflix = result.classified.find { |r| r[:description].start_with?("NETFLIX") }
        expect(netflix[:classification]).to eq("subscription")
        expect(netflix[:classifier]).to eq("ai")
        expect(netflix[:confidence]).to eq(0.95)
        expect(netflix[:inferred_service_name]).to eq("Netflix")
        expect(netflix[:inferred_category]).to eq("エンタメ")
      end

      it "non_subscription 行は classification: non_subscription になる" do
        result = classifier.classify(rows)
        eneos = result.classified.find { |r| r[:description] == "ENEOS XXX" }
        expect(eneos[:classification]).to eq("non_subscription")
        expect(eneos[:classifier]).to eq("ai")
      end

      it "PII（連続4桁以上の数字）は XXXX にマスクして送信される（NFR-S-10）" do
        captured_messages = nil
        allow(messages_resource).to receive(:create) do |**kwargs|
          captured_messages = kwargs[:messages]
          fake_message(JSON.generate(results: []))
        end
        classifier.classify(rows)
        sent_text = captured_messages.first[:content]
        expect(sent_text).to include("NETFLIX.COM XXXX")
        expect(sent_text).not_to include("1234567890")
      end

      it "system プロンプトに cache_control: ephemeral が付いている（コスト最適化）" do
        captured_system = nil
        allow(messages_resource).to receive(:create) do |**kwargs|
          captured_system = kwargs[:system_]
          fake_message(JSON.generate(results: []))
        end
        classifier.classify(rows)
        expect(captured_system.first[:cache_control]).to eq({ type: "ephemeral" })
      end

      it "row 内に内部用の :_ai_id を残さない" do
        result = classifier.classify(rows)
        result.classified.each { |r| expect(r).not_to have_key(:_ai_id) }
      end
    end

    context "API が一部の id しか返さなかった場合" do
      before do
        ai_response = fake_message(JSON.generate(
          results: [
            { id: 0, is_subscription: true, confidence: 0.9, service_name: "Netflix", category: "エンタメ" }
            # id: 1 は欠落
          ]
        ))
        allow(messages_resource).to receive(:create).and_return(ai_response)
      end

      it "結果が無い行は unclassified（unknown 扱い）になる" do
        result = classifier.classify(rows)
        expect(result.classified.size).to eq(1)
        expect(result.unclassified.size).to eq(1)
        expect(result.unclassified.first[:classification]).to eq("unknown")
      end
    end

    context "JSON パースに失敗した場合" do
      before do
        bad_response = fake_message("これは JSON ではない応答")
        allow(messages_resource).to receive(:create).and_return(bad_response)
      end

      it "全ての行が unclassified（unknown）として返る" do
        result = classifier.classify(rows)
        expect(result.classified).to be_empty
        expect(result.unclassified.size).to eq(2)
      end
    end

    context "応答が ```json ... ``` フェンスで囲まれている場合" do
      before do
        wrapped = "```json\n#{JSON.generate(results: [
          { id: 0, is_subscription: true, confidence: 0.8, service_name: "X", category: "エンタメ" },
          { id: 1, is_subscription: false, confidence: 0.7, service_name: nil, category: nil }
        ])}\n```"
        allow(messages_resource).to receive(:create).and_return(fake_message(wrapped))
      end

      it "フェンスを剥がしてパースできる" do
        result = classifier.classify(rows)
        expect(result.classified.size).to eq(2)
      end
    end

    context "API がレート制限を返した場合" do
      let(:rate_limit_class) { Class.new(StandardError) }

      before do
        # SDK の Anthropic::Errors::RateLimitError の代わりにダミー例外クラスを使うため、
        # AiClassifier 側の rescue 句に動的にこのクラスを追加する
        stub_const("Anthropic::Errors::RateLimitError", rate_limit_class)
        ok_response = fake_message(JSON.generate(
          results: [
            { id: 0, is_subscription: true, confidence: 0.9, service_name: "Netflix", category: "エンタメ" },
            { id: 1, is_subscription: false, confidence: 0.7, service_name: nil, category: nil }
          ]
        ))
        call_count = 0
        allow(messages_resource).to receive(:create) do |**_kwargs|
          call_count += 1
          if call_count < 2
            raise rate_limit_class, "rate limited"
          else
            ok_response
          end
        end
      end

      it "指数バックオフで再試行し最終的に成功する" do
        result = classifier.classify(rows)
        expect(result.classified.size).to eq(2)
        expect(messages_resource).to have_received(:create).twice
      end
    end

    context "リトライ上限まで失敗した場合" do
      let(:rate_limit_class) { Class.new(StandardError) }

      before do
        stub_const("Anthropic::Errors::RateLimitError", rate_limit_class)
        allow(messages_resource).to receive(:create).and_raise(rate_limit_class, "always failing")
      end

      it "全ての行を unclassified として返し例外は外に出さない" do
        result = classifier.classify(rows)
        expect(result.classified).to be_empty
        expect(result.unclassified.size).to eq(2)
      end
    end

    context "rows が空の場合" do
      it "API を呼ばずに空の Result を返す" do
        allow(messages_resource).to receive(:create)
        result = classifier.classify([])
        expect(result.classified).to be_empty
        expect(result.unclassified).to be_empty
        expect(messages_resource).not_to have_received(:create)
      end
    end

    context "BATCH_SIZE を超える行数" do
      it "BATCH_SIZE 件ずつ分割して API を呼び出す" do
        many_rows = Array.new(75) do |i|
          { date: Date.current, description: "TXN_#{i}", amount: BigDecimal("100") }
        end
        ok = fake_message(JSON.generate(results: []))
        allow(messages_resource).to receive(:create).and_return(ok)

        classifier.classify(many_rows)
        # 75 件 → 50 + 25 で 2 回呼ばれる
        expect(messages_resource).to have_received(:create).twice
      end
    end
  end
end
