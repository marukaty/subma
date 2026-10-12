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

      it "system プロンプトで通信費（携帯・回線・プロバイダ）をサブスク対象外と指示している（ADR-0008）" do
        captured_system = nil
        allow(messages_resource).to receive(:create) do |**kwargs|
          captured_system = kwargs[:system_]
          fake_message(JSON.generate(results: []))
        end
        classifier.classify(rows)
        prompt = captured_system.first[:text]
        expect(prompt).to include("通信費")
        expect(prompt).to match(/通信費.*is_subscription: false/)
        expect(prompt).not_to include("通信キャリア")
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

    describe "応答の値の検証" do
      let(:row) { { date: Date.new(2026, 4, 1), description: "SAMPLE SERVICE", amount: BigDecimal("980") } }

      def classify_with(entry)
        allow(messages_resource).to receive(:create)
          .and_return(fake_message(JSON.generate(results: [ { id: 0 }.merge(entry) ])))
        result = classifier.classify([ row ])
        (result.classified + result.unclassified).sole
      end

      it "is_subscription が真偽値の true のときだけサブスクにする" do
        expect(classify_with(is_subscription: true, confidence: 0.9)[:classification]).to eq("subscription")
        expect(classify_with(is_subscription: false, confidence: 0.9)[:classification]).to eq("non_subscription")
      end

      it "is_subscription が文字列・数値・null・欠落の行は unknown（文字列 \"false\" をサブスク扱いしない）" do
        [ { is_subscription: "true" }, { is_subscription: "false" }, { is_subscription: 1 },
          { is_subscription: nil }, {} ].each do |entry|
          verdict = classify_with(entry.merge(confidence: 0.9))
          expect(verdict[:classification]).to eq("unknown"), "entry=#{entry}"
          expect(verdict).not_to have_key(:classifier)
        end
      end

      it "confidence は 0..1 に収める" do
        expect(classify_with(is_subscription: true, confidence: 7)[:confidence]).to eq(1.0)
        expect(classify_with(is_subscription: true, confidence: -0.5)[:confidence]).to eq(0.0)
        expect(classify_with(is_subscription: true, confidence: nil)[:confidence]).to be_nil
      end

      it "confidence が数値でない行は unknown" do
        expect(classify_with(is_subscription: true, confidence: "0.9")[:classification]).to eq("unknown")
      end

      it "service_name・category は 100 文字に切り、空なら nil" do
        verdict = classify_with(is_subscription: true, confidence: 0.9,
                                service_name: "S" * 300, category: "  ")
        expect(verdict[:inferred_service_name]).to eq("S" * described_class::MAX_TEXT_LENGTH)
        expect(verdict[:inferred_category]).to be_nil
      end

      it "service_name・category が文字列でない行は unknown" do
        expect(classify_with(is_subscription: true, service_name: { "x" => 1 })[:classification]).to eq("unknown")
        expect(classify_with(is_subscription: true, category: [ "エンタメ" ])[:classification]).to eq("unknown")
      end

      it "results がオブジェクトの配列でない・応答全体が配列でも例外にせず unknown" do
        allow(messages_resource).to receive(:create).and_return(fake_message(JSON.generate(results: [ 1, "x" ])))
        expect(classifier.classify([ row ]).unclassified.sole[:classification]).to eq("unknown")

        allow(messages_resource).to receive(:create).and_return(fake_message("[1, 2]"))
        expect(classifier.classify([ row ]).unclassified.sole[:classification]).to eq("unknown")
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

    describe "同じ店名・金額の行をまとめて送る" do
      let(:fake) { FakeAnthropicClient.new(subscriptions: [ "AMAZON PRIME" ]) }
      let(:classifier) { described_class.new(client: fake) }

      def row(description, amount, day = 1)
        { date: Date.new(2026, 4, day), description: description, amount: BigDecimal(amount.to_s) }
      end

      it "正規化後の店名と金額が同じ行は 1 回だけ送り、結果を全行に当てる" do
        rows = [
          row("AMAZON PRIME", 600, 1),
          row("amazon prime", 600, 2),
          row("ＡＭＡＺＯＮ　ＰＲＩＭＥ", 600, 3),
          row("AMAZON  PRIME ", "600.0", 4)
        ]
        result = classifier.classify(rows)

        expect(fake.sent_rows.size).to eq(1)
        expect(result.classified.size).to eq(4)
        expect(result.classified.map { |r| r[:classification] }.uniq).to eq([ "subscription" ])
        expect(result.classified.map { |r| r[:inferred_service_name] }.uniq).to eq([ "AMAZON PRIME" ])
        # 日付・店名の表記は元の行のまま
        expect(result.classified.map { |r| r[:date].day }).to eq([ 1, 2, 3, 4 ])
        expect(result.classified.map { |r| r[:description] }).to eq(rows.map { |r| r[:description] })
      end

      it "店名が同じでも金額が違えば別々に送る（汎用の店名は金額で判定が変わる）" do
        classifier.classify([ row("AMAZON.CO.JP", 600), row("AMAZON.CO.JP", 3_280), row("AMAZON.CO.JP", 600, 2) ])
        expect(fake.sent_rows.map { |r| [ r["description"], r["amount"] ] }).to eq([ [ "AMAZON.CO.JP", "600.0" ], [ "AMAZON.CO.JP", "3280.0" ] ])
      end

      it "マスク後に同じになる店名はまとめる（AI に送る内容が同じため）" do
        classifier.classify([ row("SHOP 12345678", 500), row("SHOP 87654321", 500) ])
        expect(fake.sent_rows.size).to eq(1)
        expect(fake.sent_rows.first["description"]).to eq("SHOP XXXX")
      end

      it "100 行が同じ店名・金額でも、API に送るのは 1 行" do
        result = classifier.classify(Array.new(100) { |i| row("SAME SHOP", 1_000, (i % 28) + 1) })
        expect(fake.requests.size).to eq(1)
        expect(fake.sent_rows.size).to eq(1)
        expect(result.classified.size).to eq(100)
      end

      it "代表行の判定が得られなければ、同じキーの行はすべて unknown" do
        allow(fake).to receive(:create).and_raise(StandardError, "boom")
        result = classifier.classify([ row("X SHOP", 100), row("X SHOP", 100, 2) ])
        expect(result.unclassified.map { |r| r[:classification] }).to eq(%w[unknown unknown])
        expect(result.skipped_count).to eq(0)
      end
    end

    describe "利用量の上限（limiter）" do
      let(:fake) { FakeAnthropicClient.new }
      let(:classifier) { described_class.new(client: fake) }
      let(:limiter) { instance_double(AiUsageLimiter) }

      def row(description, amount = 100)
        { date: Date.new(2026, 4, 1), description: description, amount: BigDecimal(amount.to_s) }
      end

      it "まとめた後の件数で予約し、許された件数だけ先頭から送る" do
        allow(limiter).to receive(:reserve).with(3).and_return(2)
        rows = [ row("A"), row("B"), row("B"), row("C"), row("C") ]

        result = classifier.classify(rows, limiter: limiter)

        expect(fake.sent_rows.map { |r| r["description"] }).to eq(%w[A B])
        expect(result.classified.map { |r| r[:description] }).to eq(%w[A B B])
        expect(result.unclassified.map { |r| [ r[:description], r[:classification] ] }).to eq([ %w[C unknown], %w[C unknown] ])
        expect(result.skipped_count).to eq(2)
      end

      it "0 件しか許されなければ API を呼ばない" do
        allow(limiter).to receive(:reserve).and_return(0)
        result = classifier.classify([ row("A"), row("B") ], limiter: limiter)
        expect(fake.requests).to be_empty
        expect(result.skipped_count).to eq(2)
        expect(result.unclassified.size).to eq(2)
      end

      it "limiter を渡さなければ上限なし（skipped_count は 0）" do
        result = classifier.classify([ row("A") ])
        expect(result.skipped_count).to eq(0)
      end
    end
  end
end
