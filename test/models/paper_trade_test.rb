require "test_helper"

class PaperTradeTest < ActiveSupport::TestCase
  Sig = Struct.new(:strategy, :metadata)

  test "rules_for picks the daily rule set for swing picks" do
    assert_equal PaperTrade::RULES[:daily], PaperTrade.rules_for(Sig.new("SWING_PICK", {}))
  end

  test "rules_for picks scalp for short timeframes" do
    assert_equal PaperTrade::RULES[:scalp], PaperTrade.rules_for(Sig.new("X", { "timeframe" => "5m" }))
    assert_equal PaperTrade::RULES[:scalp], PaperTrade.rules_for(Sig.new("X", { "timeframe" => "15m" }))
  end

  test "rules_for defaults to swing" do
    assert_equal PaperTrade::RULES[:swing], PaperTrade.rules_for(Sig.new("X", { "timeframe" => "1h" }))
    assert_equal PaperTrade::RULES[:swing], PaperTrade.rules_for(Sig.new("X", {}))
  end

  test "winner? reflects pnl sign" do
    assert PaperTrade.new(pnl_pct: 3).winner?
    assert_not PaperTrade.new(pnl_pct: 0).winner?
    assert_not PaperTrade.new(pnl_pct: -2).winner?
  end

  test "winners and losers scopes only include closed trades" do
    signal = TradingSignal.create!(symbol: "X", strategy: "T", signal_type: "NEUTRAL", fired_at: Time.current)
    base = { trading_signal: signal, symbol: "X", side: "BUY", strategy: "T", entry_price: 100, entry_at: Time.current }

    win  = PaperTrade.create!(**base, status: "closed", pnl_pct: 5)
    loss = PaperTrade.create!(**base, status: "closed", pnl_pct: -5)
    PaperTrade.create!(**base, status: "open", pnl_pct: nil)

    assert_includes PaperTrade.winners, win
    assert_includes PaperTrade.losers, loss
    assert_equal 1, PaperTrade.winners.count
    assert_equal 1, PaperTrade.losers.count
    assert_equal 1, PaperTrade.open_trades.count
  end
end
