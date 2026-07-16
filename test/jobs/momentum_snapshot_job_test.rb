require "test_helper"

class MomentumSnapshotJobTest < ActiveSupport::TestCase
  def stub_ranking(picks, blocked: false)
    MomentumRankingService.class_eval do
      alias_method :__orig_call, :call
      define_method(:call) { picks }
    end
    orig = IdxMarketState.method(:long_blocked?)
    IdxMarketState.define_singleton_method(:long_blocked?) { blocked }
    yield
  ensure
    MomentumRankingService.class_eval do
      alias_method :call, :__orig_call
      remove_method :__orig_call
    end
    IdxMarketState.define_singleton_method(:long_blocked?, orig)
  end

  test "stores ranked picks with regime risk_on" do
    picks = [ { symbol: "BDMN.JK", momentum: 0.6, last_close: 4160.0 },
              { symbol: "INCO.JK", momentum: 0.32, last_close: 4930.0 } ]
    stub_ranking(picks) do
      MomentumSnapshotJob.perform_now
    end
    rows = MomentumSnapshot.picks.order(:rank)
    assert_equal %w[BDMN.JK INCO.JK], rows.pluck(:symbol)
    assert_equal [ "risk_on" ], rows.pluck(:regime).uniq
  end

  test "stores single risk_off marker when regime blocked" do
    stub_ranking([], blocked: true) do
      MomentumSnapshotJob.perform_now
    end
    assert_equal 1, MomentumSnapshot.count
    row = MomentumSnapshot.first
    assert_equal "risk_off", row.regime
    assert_nil row.symbol
  end

  test "idempotent: second run same day adds nothing" do
    stub_ranking([ { symbol: "BDMN.JK", momentum: 0.6, last_close: 4160.0 } ]) do
      MomentumSnapshotJob.perform_now
      MomentumSnapshotJob.perform_now
    end
    assert_equal 1, MomentumSnapshot.count
  end
end
