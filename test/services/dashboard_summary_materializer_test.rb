require "test_helper"

class DashboardSummaryMaterializerTest < ActiveSupport::TestCase
  test "materializes momentum tracker summary" do
    DashboardSummaryMaterializer.new.call

    summary = MomentumTrackerSummary.sole
    assert_equal 0, summary.data["tracked_days"]
    assert_equal 100.0, summary.data["equity"]
  end

  test "materializes paper trade stats summary per asset_type" do
    DashboardSummaryMaterializer.new.call

    summary = PaperTradeStatsSummary.find_by!(asset_type: "stock")
    assert_equal 0, summary.data["total_closed"]
    assert_equal 0, summary.data["open_count"]
  end

  test "re-running upserts instead of duplicating rows" do
    DashboardSummaryMaterializer.new.call
    DashboardSummaryMaterializer.new.call

    assert_equal 1, MomentumTrackerSummary.count
    assert_equal 1, PaperTradeStatsSummary.where(asset_type: "stock").count
  end

  test "serializes best/worst trade as plain hashes, not AR objects" do
    signal = TradingSignal.create!(asset_type: "stock", strategy: "SWING_PICK",
                            symbol: "AAA.JK", fired_at: 2.days.ago)
    PaperTrade.create!(asset_type: "stock", strategy: "SWING_PICK", symbol: "AAA.JK",
                       side: "long", status: "closed", entry_price: 100, entry_at: 2.days.ago,
                       exit_price: 110, exit_at: 1.day.ago, pnl_pct: 10.0,
                       trading_signal_id: signal.id)

    DashboardSummaryMaterializer.new.call

    summary = PaperTradeStatsSummary.find_by!(asset_type: "stock")
    assert_equal "AAA.JK", summary.data["best_trade"]["symbol"]
    assert_equal 10.0, summary.data["best_trade"]["pnl_pct"]
  end
end
