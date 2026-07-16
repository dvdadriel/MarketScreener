require "test_helper"

class AiRecommenderServiceTest < ActiveSupport::TestCase
  # Replace NvidiaNimClient#chat with a proc returning `value` for the block.
  def stub_chat(value)
    NvidiaNimClient.class_eval do
      alias_method :__orig_chat, :chat
      define_method(:chat) { |**| value }
    end
    yield
  ensure
    NvidiaNimClient.class_eval do
      alias_method :chat, :__orig_chat
      remove_method :__orig_chat
    end
  end

  def sig(id, symbol: "S#{id}")
    s = TradingSignal.new(symbol: symbol, strategy: "SQUEEZE_BREAKOUT",
                          signal_type: "BUY", score: 0.8, metadata: {})
    s.id = id
    s
  end

  test "ok with resolved picks capped at 3" do
    signals = (1..5).map { |i| sig(i) }
    picks   = (1..5).map { |i| { "id" => i, "reason" => "alasan #{i}" } }
    stub_chat({ "picks" => picks }) do
      r = AiRecommenderService.new(signals).call
      assert_equal :ok, r[:status]
      assert_equal 3, r[:picks].size
      assert_equal 1, r[:picks].first[:signal].id
      assert_equal "alasan 1", r[:picks].first[:reason]
    end
  end

  test "none when picks empty" do
    stub_chat({ "picks" => [] }) do
      assert_equal :none, AiRecommenderService.new([ sig(1) ]).call[:status]
    end
  end

  test "none when all ids unknown" do
    stub_chat({ "picks" => [ { "id" => 999, "reason" => "x" } ] }) do
      assert_equal :none, AiRecommenderService.new([ sig(1) ]).call[:status]
    end
  end

  test "unavailable when nim returns nil" do
    stub_chat(nil) do
      assert_equal :unavailable, AiRecommenderService.new([ sig(1) ]).call[:status]
    end
  end

  test "unavailable for empty input without calling nim" do
    stub_chat(->{ flunk("nim should not be called") }) do
      assert_equal :unavailable, AiRecommenderService.new([]).call[:status]
    end
  end
end
