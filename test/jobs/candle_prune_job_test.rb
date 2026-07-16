require "test_helper"

class CandlePruneJobTest < ActiveSupport::TestCase
  def make_candle(timeframe:, opened_at:)
    Candle.create!(
      symbol: "BTCUSDT", timeframe: timeframe, asset_type: "crypto",
      open: 100, high: 101, low: 99, close: 100, volume: 10, opened_at: opened_at
    )
  end

  test "deletes candles older than the per-timeframe retention window" do
    # 5m retention is 30 days
    old_5m   = make_candle(timeframe: "5m", opened_at: 40.days.ago)
    fresh_5m = make_candle(timeframe: "5m", opened_at: 1.day.ago)
    # 1d retention is 3 years — a 40-day-old daily candle should survive
    old_1d   = make_candle(timeframe: "1d", opened_at: 40.days.ago)

    deleted = CandlePruneJob.new.perform

    assert_equal 1, deleted
    assert_not Candle.exists?(old_5m.id)
    assert Candle.exists?(fresh_5m.id)
    assert Candle.exists?(old_1d.id)
  end
end
