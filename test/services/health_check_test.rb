require "test_helper"

class HealthCheckTest < ActiveSupport::TestCase
  # Stub IdxMarket.open_now? untuk blok, lalu PULIHKAN method asli (bukan hapus).
  def with_market(open:)
    original = IdxMarket.method(:open_now?)
    IdxMarket.define_singleton_method(:open_now?) { open }
    yield
  ensure
    IdxMarket.define_singleton_method(:open_now?, original)
  end

  def stock_candle(opened_at:)
    Candle.create!(
      symbol: "BBCA.JK", timeframe: "1h", asset_type: "stock",
      open: 100, high: 101, low: 99, close: 100, volume: 10, opened_at: opened_at
    )
  end

  test "database check passes against a live connection" do
    assert HealthCheck.run.checks[:database][:ok]
  end

  # Crypto off (CRYPTO_ENABLED=false): freshness check = stock, sadar jam bursa.
  test "stock_freshness ok with a recent 1h candle during market hours" do
    with_market(open: true) do
      stock_candle(opened_at: 10.minutes.ago)
      assert HealthCheck.run.checks[:stock_freshness][:ok]
    end
  end

  test "stock_freshness fails when candles are stale during market hours" do
    with_market(open: true) do
      stock_candle(opened_at: 3.hours.ago)
      assert_not HealthCheck.run.checks[:stock_freshness][:ok]
    end
  end

  test "stock_freshness ok (skipped) when market is closed" do
    with_market(open: false) do
      assert HealthCheck.run.checks[:stock_freshness][:ok]
    end
  end

  test "crypto_freshness check absent when crypto disabled" do
    assert_nil HealthCheck.run.checks[:crypto_freshness]
  end

  # Plan H5: watchdog MomentumSnapshotJob gagal diam-diam.
  test "momentum_freshness ok on weekend regardless of snapshot state" do
    sunday = Time.utc(2026, 7, 19, 10)   # 2026-07-19 = Minggu
    travel_to(sunday) { assert HealthCheck.run.checks[:momentum_freshness][:ok] }
  end

  test "momentum_freshness ok before daily cutoff even with no snapshot" do
    weekday_morning = Time.utc(2026, 7, 16, 3)   # 2026-07-16 Kamis, 10:00 WIB (< cutoff 17:30)
    travel_to(weekday_morning) { assert HealthCheck.run.checks[:momentum_freshness][:ok] }
  end

  test "momentum_freshness fails after cutoff when today has no snapshot" do
    weekday_evening = Time.utc(2026, 7, 16, 11)   # 18:00 WIB (> cutoff 17:30)
    travel_to(weekday_evening) do
      assert_not HealthCheck.run.checks[:momentum_freshness][:ok]
    end
  end

  test "momentum_freshness ok after cutoff when today's snapshot exists" do
    weekday_evening = Time.utc(2026, 7, 16, 11)
    travel_to(weekday_evening) do
      MomentumSnapshot.create!(snapshot_date: Date.new(2026, 7, 16), regime: "risk_off")
      assert HealthCheck.run.checks[:momentum_freshness][:ok]
    end
  end

  test "Result aggregates healthy? and degraded" do
    healthy = HealthCheck::Result.new(checks: { a: { ok: true }, b: { ok: true } })
    assert healthy.healthy?
    assert_empty healthy.degraded

    degraded = HealthCheck::Result.new(checks: { a: { ok: true }, b: { ok: false } })
    assert_not degraded.healthy?
    assert_equal [ :b ], degraded.degraded
  end
end
