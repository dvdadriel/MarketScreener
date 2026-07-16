require "test_helper"

class IndicatorServiceTest < ActiveSupport::TestCase
  # Build unsaved Candle objects — IndicatorService only reads close/high/low/volume.
  def candles(closes, high_offset: 1, low_offset: 1, volume: 100)
    closes.each_with_index.map do |c, i|
      Candle.new(
        symbol: "X", timeframe: "1h", asset_type: "crypto",
        open: c, high: c + high_offset, low: c - low_offset, close: c,
        volume: volume, opened_at: Time.at(i * 3600).utc
      )
    end
  end

  test "sma averages the last N closes" do
    svc = IndicatorService.new(candles((1..50).to_a))
    assert_in_delta 25.5, svc.sma(period: 50), 0.0001
    assert_in_delta 50.0, svc.last_close, 0.0001
  end

  test "sma returns nil when not enough data" do
    assert_nil IndicatorService.new(candles([ 1, 2, 3 ])).sma(period: 50)
  end

  test "rsi is 100 for a strictly rising series" do
    assert_in_delta 100.0, IndicatorService.new(candles((1..20).to_a)).rsi(period: 14), 0.0001
  end

  test "rsi is 0 for a strictly falling series" do
    assert_in_delta 0.0, IndicatorService.new(candles(20.downto(1).to_a)).rsi(period: 14), 0.0001
  end

  test "atr equals the constant true range" do
    # constant close with +/-1 wick => true range is 2 every bar
    svc = IndicatorService.new(candles(Array.new(20, 100.0)))
    assert_in_delta 2.0, svc.atr(period: 14), 0.0001
  end

  test "macd returns the expected keys" do
    macd = IndicatorService.new(candles((1..50).to_a)).macd
    assert_kind_of Float, macd[:macd]
    assert_equal %i[macd signal histogram prev_histogram].sort, macd.keys.sort
  end

  test "bollinger collapses to the mean with zero variance" do
    b = IndicatorService.new(candles(Array.new(20, 100.0))).bollinger(period: 20)
    assert_in_delta 100.0, b[:upper], 0.0001
    assert_in_delta 100.0, b[:middle], 0.0001
    assert_in_delta 100.0, b[:lower], 0.0001
  end

  test "trend_bias reflects price relative to EMA" do
    assert_equal :bullish, IndicatorService.new(candles((1..60).to_a)).trend_bias
    assert_equal :bearish, IndicatorService.new(candles(60.downto(1).to_a)).trend_bias
    assert_equal :neutral, IndicatorService.new(candles(Array.new(60, 100.0))).trend_bias
  end
end
