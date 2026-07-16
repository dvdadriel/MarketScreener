require "test_helper"

class TradingSignalTest < ActiveSupport::TestCase
  def build_signal(attrs = {})
    TradingSignal.new({
      symbol: "BTCUSDT", strategy: "TEST", signal_type: "BUY",
      asset_type: "crypto", fired_at: Time.current, score: 0.8
    }.merge(attrs))
  end

  test "valid with required attributes" do
    assert build_signal.valid?
  end

  test "requires symbol, strategy and fired_at" do
    s = build_signal(symbol: nil, strategy: nil, fired_at: nil)
    assert_not s.valid?
    assert s.errors.of_kind?(:symbol, :blank)
    assert s.errors.of_kind?(:strategy, :blank)
    assert s.errors.of_kind?(:fired_at, :blank)
  end

  test "rejects out-of-range score" do
    assert_not build_signal(score: 1.5).valid?
    assert_not build_signal(score: -0.1).valid?
    assert build_signal(score: nil).valid?
  end

  test "rejects unknown signal_type" do
    assert_not build_signal(signal_type: "HODL").valid?
  end

  test "score_pct rounds to a percentage" do
    assert_equal 73, build_signal(score: 0.731).score_pct
    assert_equal 0, build_signal(score: nil).score_pct
  end

  test "badge_color maps by signal type" do
    assert_includes build_signal(signal_type: "BUY").badge_color, "green"
    assert_includes build_signal(signal_type: "SELL").badge_color, "red"
  end
end
