require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  # Stub IdxMarket.open_now? deterministik (stock_freshness sadar jam bursa); pulihkan asli.
  def with_market(open:)
    original = IdxMarket.method(:open_now?)
    IdxMarket.define_singleton_method(:open_now?) { open }
    yield
  ensure
    IdxMarket.define_singleton_method(:open_now?, original)
  end

  def make_healthy!
    SolidQueue::Process.create!(kind: "Scheduler", name: "sched-test", pid: 1, last_heartbeat_at: Time.current)
    SolidQueue::Process.create!(kind: "Worker", name: "worker-test", pid: 2, last_heartbeat_at: Time.current)
    SolidQueue::Job.create!(class_name: "X", queue_name: "default", finished_at: Time.current)
    Candle.create!(
      symbol: "BBCA.JK", timeframe: "1h", asset_type: "stock",
      open: 100, high: 101, low: 99, close: 100, volume: 10, opened_at: 5.minutes.ago
    )
  end

  test "returns 200 and ok status when all checks pass" do
    with_market(open: true) do
      make_healthy!
      get health_url

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "ok", body["status"]
      assert_empty body["degraded"]
    end
  end

  test "returns 503 and degraded status when checks fail" do
    # Market buka tapi tak ada worker/candle/job selesai -> degraded.
    with_market(open: true) do
      get health_url

      assert_response :service_unavailable
      body = JSON.parse(response.body)
      assert_equal "degraded", body["status"]
      assert_includes body["degraded"], "stock_freshness"
      assert_includes body["degraded"], "queue_workers"
    end
  end
end
