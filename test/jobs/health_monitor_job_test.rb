require "test_helper"

class HealthMonitorJobTest < ActiveSupport::TestCase
  test "runs cleanly when degraded (no data, no workers, Telegram unconfigured)" do
    assert_nothing_raised { HealthMonitorJob.new.perform }
  end

  test "runs cleanly when healthy" do
    SolidQueue::Process.create!(kind: "Scheduler", name: "sched-test", pid: 1, last_heartbeat_at: Time.current)
    SolidQueue::Process.create!(kind: "Worker", name: "worker-test", pid: 2, last_heartbeat_at: Time.current)
    Candle.create!(
      symbol: "BTCUSDT", timeframe: "5m", asset_type: "crypto",
      open: 100, high: 101, low: 99, close: 100, volume: 10, opened_at: 1.minute.ago
    )

    assert_nothing_raised { HealthMonitorJob.new.perform }
  end
end
