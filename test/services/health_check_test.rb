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

  test "Result aggregates healthy? and degraded" do
    healthy = HealthCheck::Result.new(checks: { a: { ok: true }, b: { ok: true } })
    assert healthy.healthy?
    assert_empty healthy.degraded

    degraded = HealthCheck::Result.new(checks: { a: { ok: true }, b: { ok: false } })
    assert_not degraded.healthy?
    assert_equal [ :b ], degraded.degraded
  end
end
