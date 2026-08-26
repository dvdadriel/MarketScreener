require "test_helper"

class MomentumGateEvaluatorTest < ActiveSupport::TestCase
  def index_candle(date, close)
    Candle.create!(symbol: IdxMarketState::SYMBOL, timeframe: "1d", asset_type: "index",
                   open: close, high: close, low: close, close: close, volume: 1,
                   opened_at: Time.utc(date.year, date.month, date.day, 12))
  end

  test "not evaluated before duration threshold" do
    d0 = Date.current - 10
    MomentumSnapshot.create!(snapshot_date: d0, regime: "risk_off")
    MomentumSnapshot.create!(snapshot_date: Date.current, regime: "risk_off")

    v = MomentumGateEvaluator.new.call
    refute v.evaluated
    refute v.promote
    assert_equal 8, v.weeks_required
  end

  test "promotes when all four criteria pass after 8+ weeks" do
    d0 = Date.current - 60   # > 8 minggu
    [ d0, Date.current ].each { |d| index_candle(d, 100.0) }
    MomentumSnapshot.create!(snapshot_date: d0, regime: "risk_on", rank: 1,
                             symbol: "AAA.JK", momentum: 0.1, price: 100.0)
    MomentumSnapshot.create!(snapshot_date: Date.current, regime: "risk_on", rank: 1,
                             symbol: "AAA.JK", momentum: 0.2, price: 110.0)
    Candle.create!(symbol: "AAA.JK", timeframe: "1d", asset_type: "stock",
                   open: 100, high: 110, low: 100, close: 110, volume: 1,
                   opened_at: Time.utc(Date.current.year, Date.current.month, Date.current.day))

    v = MomentumGateEvaluator.new.call
    assert v.evaluated
    assert v.criteria[:duration]
    assert v.criteria[:regime]
    # IHSG flat (100->100) sementara paper naik → alpha positif & DD kecil.
    assert v.criteria[:alpha]
    assert v.criteria[:drawdown]
    assert v.promote
  end

  test "fails regime criterion when a risk_off day has a pick (data integrity check)" do
    d0 = Date.current - 60
    MomentumSnapshot.create!(snapshot_date: d0, regime: "risk_off", rank: 1,
                             symbol: "BAD.JK", momentum: 0.1, price: 100.0)   # pelanggaran
    v = MomentumGateEvaluator.new.call
    refute v.criteria[:regime]
    refute v.promote
  end

  test "fails alpha criterion when paper underperforms IHSG" do
    d0 = Date.current - 60
    index_candle(d0, 100.0)
    index_candle(Date.current, 150.0)   # IHSG naik tajam
    MomentumSnapshot.create!(snapshot_date: d0, regime: "risk_on", rank: 1,
                             symbol: "AAA.JK", momentum: 0.1, price: 100.0)
    MomentumSnapshot.create!(snapshot_date: Date.current, regime: "risk_on", rank: 1,
                             symbol: "AAA.JK", momentum: 0.0, price: 100.0)   # paper flat
    Candle.create!(symbol: "AAA.JK", timeframe: "1d", asset_type: "stock",
                   open: 100, high: 100, low: 100, close: 100, volume: 1,
                   opened_at: Time.utc(Date.current.year, Date.current.month, Date.current.day))

    v = MomentumGateEvaluator.new.call
    refute v.criteria[:alpha]
    refute v.promote
  end
end
