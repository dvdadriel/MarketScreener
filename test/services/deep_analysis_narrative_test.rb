require "test_helper"

class DeepAnalysisNarrativeTest < ActiveSupport::TestCase
  RESULT = {
    display:        "BTC",
    recommendation: { verdict: "BUY", confidence: "HIGH", score: 80, reason: "x" },
    confluence:     nil,
    timeframes:     { "1h" => { has_data: true, rsi: 30, trend_bias: :bullish } }
  }.freeze

  class FakeClient
    def initialize(ret) = @ret = ret
    def chat(**) = @ret
  end

  # Override NvidiaNimClient.new to return `fake` for the block, then restore.
  def with_client(fake)
    singleton = NvidiaNimClient.singleton_class
    orig = NvidiaNimClient.method(:new)
    singleton.define_method(:new) { |*a, **k| fake }
    yield
  ensure
    singleton.define_method(:new) { |*a, **k| orig.call(*a, **k) }
  end

  test "build_narrative returns client text" do
    with_client(FakeClient.new("narasi oke")) do
      out = DeepAnalysisService.new("BTCUSDT").send(:build_narrative, RESULT)
      assert_equal "narasi oke", out
    end
  end

  test "build_narrative is nil when client returns nil (no key)" do
    with_client(FakeClient.new(nil)) do
      assert_nil DeepAnalysisService.new("BTCUSDT").send(:build_narrative, RESULT)
    end
  end
end
