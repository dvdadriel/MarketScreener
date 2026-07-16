require "test_helper"
require "ostruct"

class BacktestServiceTest < ActiveSupport::TestCase
  def svc = BacktestService.new(symbols: [])

  def bar(o, h, l, c, day)
    OpenStruct.new(open: o, high: h, low: l, close: c, opened_at: Time.utc(2026, 1, 1) + day.days)
  end

  # BUY signal: entry di open bar index 1 (=100), SL -5% (95), TP +10% (110).
  # sl_pct/tp_pct ada di metadata — bentuk yang sama dengan output evaluate().
  def buy_sig
    { symbol: "AAA.JK", strategy: "CONFLUENCE_BULLISH", signal_type: "BUY",
      metadata: { timeframe: "multi", sl_pct: -5.0, tp_pct: 10.0 } }
  end

  test "exits at TP when high crosses target" do
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(102, 111, 101, 110, 2) ]
    t = svc.send(:simulate, buy_sig, bars, 1)
    assert_equal "TP", t.exit_reason
    assert_in_delta 10.0, t.pnl_pct, 0.01
  end

  test "exits at SL when low crosses stop" do
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(96, 98, 94, 95, 2) ]
    t = svc.send(:simulate, buy_sig, bars, 1)
    assert_equal "SL", t.exit_reason
    assert_in_delta(-5.0, t.pnl_pct, 0.01)
  end

  test "SL wins over TP when both hit in the same bar (conservative)" do
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(100, 111, 94, 100, 2) ]
    t = svc.send(:simulate, buy_sig, bars, 1)
    assert_equal "SL", t.exit_reason
  end

  test "time-exit at last close when neither SL nor TP hit" do
    # 3 bar, tak ada yang sentuh 95/110 -> tutup di close bar terakhir (104).
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(102, 105, 98, 104, 2) ]
    t = svc.send(:simulate, buy_sig, bars, 1)
    assert_equal "TIME", t.exit_reason
    assert_in_delta 4.0, t.pnl_pct, 0.01
  end

  test "SELL trade profits when price falls" do
    sell = buy_sig.merge(signal_type: "SELL", strategy: "SQUEEZE_BREAKOUT",
                          metadata: { timeframe: "1d", sl_pct: 5.0, tp_pct: -10.0 })
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(95, 96, 89, 90, 2) ]
    t = svc.send(:simulate, sell, bars, 1)
    assert_equal "TP", t.exit_reason           # TP = 90 (turun 10%)
    assert_in_delta 10.0, t.pnl_pct, 0.01
  end

  test "gap-through stop fills at the open, not at the SL level" do
    # bar entry gap-DOWN: open 90 < SL 95 -> isi di 90 (rugi -10%, bukan -5%).
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(90, 92, 88, 91, 2) ]
    t = svc.send(:simulate, buy_sig, bars, 1)
    assert_equal "SL", t.exit_reason
    assert_in_delta(-10.0, t.pnl_pct, 0.01)   # gap worse than the -5% stop
  end

  test "slippage reduces pnl on both legs" do
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(102, 113, 101, 110, 2) ]
    clean = BacktestService.new(symbols: [], slippage_pct: 0.0).send(:simulate, buy_sig, bars, 1)
    slipd = BacktestService.new(symbols: [], slippage_pct: 1.0).send(:simulate, buy_sig, bars, 1)
    assert_operator slipd.pnl_pct, :<, clean.pnl_pct - 1.0   # slippage menggerus pnl
  end

  test "cost_pct is deducted from each trade pnl" do
    svc_fee = BacktestService.new(symbols: [], cost_pct: 0.4)
    bars = [ bar(0, 0, 0, 0, 0), bar(100, 101, 99, 100, 1), bar(102, 111, 101, 110, 2) ]
    t = svc_fee.send(:simulate, buy_sig, bars, 1)
    assert_in_delta 9.6, t.pnl_pct, 0.01   # TP +10% − 0.4% fee
  end

  test "sized_metrics: real drawdown is bounded and equity compounds" do
    svc_sized = BacktestService.new(symbols: [], risk_pct: 1.0)
    # sl_pct -5% → posisi 1/5 = 20% ekuitas. Stop-out murni = -20%×5% = -1% ekuitas.
    win  = BacktestService::Trade.new(pnl_pct: 10.0, sl_pct: -5.0, exit_at: Time.utc(2026, 1, 1))
    loss = BacktestService::Trade.new(pnl_pct: -5.0, sl_pct: -5.0, exit_at: Time.utc(2026, 1, 2))
    m = svc_sized.send(:sized_metrics, [ win, loss ])
    # equity: 100 → ×(1+0.2×0.10)=102 → ×(1+0.2×-0.05)=100.98
    assert_in_delta 0.98, m[:total_return], 0.05
    assert_in_delta 1.0,  m[:max_drawdown_real], 0.1   # DD dari puncak 102 ke 100.98 ≈ 1%
  end

  test "sized_metrics nil when risk_pct is zero" do
    assert_nil svc.send(:sized_metrics, [ BacktestService::Trade.new(pnl_pct: 5, sl_pct: -5, exit_at: Time.utc(2026, 1, 1)) ])
  end

  test "position size capped at 100% (no leverage) for tight stops" do
    svc_sized = BacktestService.new(symbols: [], risk_pct: 1.0)
    # sl_pct -0.5% → risk/sl = 2.0, di-cap ke 1.0 (100% ekuitas), bukan 200%.
    t = BacktestService::Trade.new(pnl_pct: 10.0, sl_pct: -0.5, exit_at: Time.utc(2026, 1, 1))
    m = svc_sized.send(:sized_metrics, [ t ])
    assert_in_delta 10.0, m[:total_return], 0.01   # 100% × 10% = 10%, bukan 20%
  end

  test "strategy_group folds CONFLUENCE_* together" do
    tr = BacktestService::Trade.new(strategy: "CONFLUENCE_BEARISH")
    assert_equal "CONFLUENCE", tr.strategy_group
    tr2 = BacktestService::Trade.new(strategy: "SQUEEZE_BREAKOUT")
    assert_equal "SQUEEZE_BREAKOUT", tr2.strategy_group
  end
end
