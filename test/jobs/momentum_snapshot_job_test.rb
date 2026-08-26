require "test_helper"

class MomentumSnapshotJobTest < ActiveSupport::TestCase
  # Guard H4 butuh candle stock 1d untuk lolos "fresh enough". Index kosong →
  # stale_trading_days = 0 (trivially fresh) — cukup untuk skenario non-freshness.
  setup do
    Candle.create!(symbol: "AAA.JK", timeframe: "1d", asset_type: "stock",
                   open: 100, high: 100, low: 100, close: 100, volume: 1,
                   opened_at: 1.day.ago)
  end

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

  test "H4: skips recording when stock candle data is stale (>2 trading days behind index)" do
    # stock candle di-setup 1 hari lalu (fresh); tambah 3 candle index SETELAHNYA
    # supaya stock jadi "3 hari bursa" ketinggalan → basi.
    3.times { |i| Candle.create!(symbol: IdxMarketState::SYMBOL, timeframe: "1d", asset_type: "index",
                                 open: 1, high: 1, low: 1, close: 1, volume: 1, opened_at: (i + 1).hours.ago) }
    stub_ranking([ { symbol: "BDMN.JK", momentum: 0.6, last_close: 4160.0 } ]) do
      MomentumSnapshotJob.perform_now
    end
    assert_equal 0, MomentumSnapshot.count, "data basi harusnya tidak direkam"
  end

  test "H3: backfills missing trading days before recording today" do
    today = Time.current.in_time_zone(IdxMarket::TZ).to_date
    gap_day = today - 2
    last_recorded = today - 5

    # Kalender index: last_recorded, gap_day, today (hari bursa berurutan).
    # Time.utc eksplisit (bukan Date#to_time.utc) — hindari geser tanggal akibat
    # konversi timezone lokal saat perbandingan opened_at.to_date nanti.
    [ last_recorded, gap_day, today ].each do |d|
      Candle.create!(symbol: IdxMarketState::SYMBOL, timeframe: "1d", asset_type: "index",
                     open: 6000, high: 6000, low: 6000, close: 6000, volume: 1,
                     opened_at: Time.utc(d.year, d.month, d.day, 12))   # tengah hari UTC, aman dari geser tz
    end
    MomentumSnapshot.create!(snapshot_date: last_recorded, regime: "risk_on", rank: 1,
                             symbol: "AAA.JK", momentum: 0.1, price: 100)

    stub_ranking([ { symbol: "BDMN.JK", momentum: 0.6, last_close: 4160.0 } ]) do
      MomentumSnapshotJob.perform_now
    end

    assert MomentumSnapshot.taken_for?(gap_day), "hari bolong harusnya di-backfill"
    assert MomentumSnapshot.taken_for?(today), "hari ini harusnya tetap direkam"
  end
end
