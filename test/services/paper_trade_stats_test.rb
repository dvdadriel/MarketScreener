require "test_helper"

class PaperTradeStatsTest < ActiveSupport::TestCase
  def make_trade(asset_type:, pnl:, status: "closed", strategy: "TEST")
    signal = TradingSignal.create!(
      symbol: "BTCUSDT", strategy: strategy, signal_type: "NEUTRAL",
      asset_type: asset_type, fired_at: Time.current
    )
    PaperTrade.create!(
      trading_signal: signal, symbol: "BTCUSDT", asset_type: asset_type,
      side: "BUY", strategy: strategy, entry_price: 100, entry_at: Time.current,
      status: status, pnl_pct: pnl
    )
  end

  test "computes win rate and averages over closed trades only" do
    make_trade(asset_type: "crypto", pnl: 10)
    make_trade(asset_type: "crypto", pnl: 4)
    make_trade(asset_type: "crypto", pnl: -6)
    make_trade(asset_type: "crypto", pnl: nil, status: "open") # ignored in closed stats

    stats = PaperTradeStats.for("crypto")

    assert_equal 3, stats[:total_closed]
    assert_equal 2, stats[:winners]
    assert_equal 1, stats[:losers]
    assert_in_delta 66.7, stats[:win_rate], 0.1
    assert_in_delta 2.67, stats[:avg_pnl], 0.01
    assert_equal 1, stats[:open_count]
  end

  test "isolates stats by asset type" do
    make_trade(asset_type: "crypto", pnl: 5)
    make_trade(asset_type: "stock",  pnl: -3)

    assert_equal 1, PaperTradeStats.for("crypto")[:total_closed]
    assert_equal 1, PaperTradeStats.for("stock")[:total_closed]
  end

  test "returns zeros with no trades" do
    stats = PaperTradeStats.for("crypto")
    assert_equal 0, stats[:total_closed]
    assert_equal 0, stats[:win_rate]
    assert_equal 0.0, stats[:avg_pnl]
  end

  # exit order [+10, -6, +4] → equity 10, 4, 8. Peak 10, trough 4 → max DD 6.
  def make_closed_with_exit(pnl:, exit_at:)
    t = make_trade(asset_type: "stock", pnl: pnl)
    t.update!(exit_at: exit_at)
    t
  end

  test "computes profit factor, max drawdown, sharpe over closed trades" do
    base = Time.current
    make_closed_with_exit(pnl: 10, exit_at: base)
    make_closed_with_exit(pnl: -6, exit_at: base + 1.minute)
    make_closed_with_exit(pnl: 4,  exit_at: base + 2.minutes)

    stats = PaperTradeStats.for("stock")

    assert_in_delta 2.33, stats[:profit_factor], 0.01   # (10+4)/6
    assert_in_delta 6.0,  stats[:max_drawdown], 0.01    # peak 10 → trough 4
    assert_in_delta 0.40, stats[:sharpe], 0.02          # mean 2.67 / std 6.60
    assert_in_delta 2.67, stats[:expectancy], 0.01      # = avg_pnl
  end

  test "profit factor nil when no losing trades" do
    make_trade(asset_type: "stock", pnl: 5)
    make_trade(asset_type: "stock", pnl: 3)
    stats = PaperTradeStats.for("stock")
    assert_nil stats[:profit_factor]
    assert_in_delta 0.0, stats[:max_drawdown], 0.01     # monotonically up
  end

  test "risk metrics nil with no closed trades" do
    stats = PaperTradeStats.for("crypto")
    assert_nil stats[:profit_factor]
    assert_nil stats[:max_drawdown]
    assert_nil stats[:sharpe]
  end
end
