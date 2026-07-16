require "test_helper"

class SetupLabelerTest < ActiveSupport::TestCase
  def sig(strategy:, metadata: {})
    TradingSignal.new(strategy: strategy, metadata: metadata)
  end

  test "squeeze breakout" do
    assert_equal "Squeeze Breakout", SetupLabeler.label(sig(strategy: "SQUEEZE_BREAKOUT"))
  end

  test "confluence oversold" do
    s = sig(strategy: "CONFLUENCE_BULLISH",
            metadata: { "checks" => [ { "name" => "rsi(28.5)", "dir" => "bullish", "tf" => "1h" } ] })
    assert_equal "Jenuh Jual (Oversold)", SetupLabeler.label(s)
  end

  test "confluence overbought" do
    s = sig(strategy: "CONFLUENCE_BEARISH",
            metadata: { "checks" => [ { "name" => "rsi(72.0)", "dir" => "bearish", "tf" => "1h" } ] })
    assert_equal "Jenuh Beli (Overbought)", SetupLabeler.label(s)
  end

  test "confluence trend when rsi mid" do
    s = sig(strategy: "CONFLUENCE_BULLISH",
            metadata: { "checks" => [ { "name" => "rsi(50.0)", "dir" => "bullish", "tf" => "1h" } ] })
    assert_equal "Trend Confluence", SetupLabeler.label(s)
  end

  test "confluence trend when no rsi check" do
    s = sig(strategy: "CONFLUENCE_BULLISH",
            metadata: { "checks" => [ { "name" => "macd", "dir" => "bullish", "tf" => "1h" } ] })
    assert_equal "Trend Confluence", SetupLabeler.label(s)
  end

  test "unknown strategy returns raw string" do
    assert_equal "FOO", SetupLabeler.label(sig(strategy: "FOO"))
  end
end
