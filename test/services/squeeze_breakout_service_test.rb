require "test_helper"

class SqueezeBreakoutServiceTest < ActiveSupport::TestCase
  SYMBOL = "TESTUSDT"

  # Persist candles for SYMBOL/1h/crypto from an array of closes.
  # volumes: optional per-bar volume (defaults 100 each).
  def seed(closes, volumes: nil, high_offset: 0.5, low_offset: 0.5)
    Candle.where(symbol: SYMBOL).delete_all
    closes.each_with_index do |c, i|
      Candle.create!(
        symbol: SYMBOL, timeframe: "1h", asset_type: "crypto",
        open: c, high: c + high_offset, low: c - low_offset, close: c,
        volume: (volumes ? volumes[i] : 100), opened_at: Time.at(i * 3600).utc
      )
    end
  end

  # 170 wide-oscillating bars, then 27 very tight bars (squeeze), then a breakout bar.
  def squeeze_then_breakout_closes
    wide  = Array.new(170) { |i| i.even? ? 90.0 : 110.0 }
    tight = Array.new(28, 100.0)          # bars 170..197 (band collapses)
    wide + tight
  end

  test "fires BUY on squeeze then upside breakout with volume" do
    closes  = squeeze_then_breakout_closes + [ 130.0 ]   # last bar breaks 20-bar high
    volumes = Array.new(closes.length - 1, 100) + [ 400 ]
    seed(closes, volumes: volumes)

    result = SqueezeBreakoutService.new(symbol: SYMBOL, asset_type: "crypto").evaluate

    refute_nil result, "expected a signal"
    assert_equal "SQUEEZE_BREAKOUT", result[:strategy]
    assert_equal "BUY", result[:signal_type]
    assert_operator result[:metadata][:bb_width_pctl], :<=, 15.0
    assert_operator result[:metadata][:vol_ratio], :>=, 1.5
    assert result[:metadata][:entry_price].positive?
  end

  test "no signal in choppy range without squeeze" do
    closes = Array.new(200) { |i| i.even? ? 90.0 : 110.0 }   # never tightens
    seed(closes)

    assert_nil SqueezeBreakoutService.new(symbol: SYMBOL, asset_type: "crypto").evaluate
  end

  test "no signal when breakout lacks volume confirmation" do
    closes = squeeze_then_breakout_closes + [ 130.0 ]
    seed(closes)   # all volumes equal => ratio ~1.0 < 1.5

    assert_nil SqueezeBreakoutService.new(symbol: SYMBOL, asset_type: "crypto").evaluate
  end
end
