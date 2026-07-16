require "test_helper"

class MomentumPaperTrackerTest < ActiveSupport::TestCase
  def snap(date, regime: "risk_on", picks: [])
    if picks.empty?
      MomentumSnapshot.create!(snapshot_date: date, regime: regime)
    else
      picks.each_with_index do |(sym, price), i|
        MomentumSnapshot.create!(snapshot_date: date, regime: regime, rank: i + 1,
                                 symbol: sym, momentum: 0.3, price: price)
      end
    end
  end

  def candle(sym, date, close)
    Candle.create!(symbol: sym, timeframe: "1d", asset_type: "stock",
                   open: close, high: close, low: close, close: close, volume: 1_000_000,
                   opened_at: date.to_time.utc)
  end

  test "empty report with no snapshots" do
    r = MomentumPaperTracker.new.call
    assert_equal 0, r[:tracked_days]
    assert_equal 100.0, r[:equity]
  end

  test "compounds daily equity from candle prices after inception rebalance" do
    d0 = Date.new(2026, 7, 1)
    d1 = Date.new(2026, 7, 2)
    snap(d0, picks: [ [ "AAA.JK", 100.0 ] ])
    snap(d1, picks: [ [ "AAA.JK", 110.0 ] ])
    candle("AAA.JK", d0, 100.0)
    candle("AAA.JK", d1, 110.0)   # +10% hari berikutnya

    r = MomentumPaperTracker.new.call
    # inception: fee 1 posisi masuk = 0.4%*1/10 = 0.04% → equity 99.96, lalu +10%
    assert_in_delta 109.96, r[:equity], 0.05
    assert_equal %w[AAA.JK], r[:holdings]
  end

  test "risk-off snapshot keeps portfolio in cash" do
    d0 = Date.new(2026, 7, 1)
    snap(d0, regime: "risk_off")
    r = MomentumPaperTracker.new.call
    assert_equal [], r[:holdings]
    assert_equal "risk_off", r[:regime_today]
    assert_in_delta 100.0, r[:equity], 0.001   # cash, tanpa fee
  end
end
