# Single source of truth for "is the radar actually working?", used by both the
# /health endpoint (for external uptime monitors) and HealthMonitorJob (which
# alerts on Telegram). Catches the "looks up but silently stopped working" class
# that launchd KeepAlive and FailedJobAlertJob miss.
class HealthCheck
  # Crypto polls every minute, 24/7, so 5m candles should never be this stale.
  CRYPTO_STALE_AFTER  = 15.minutes
  # Stock 1h polled every ~30 min saat market buka; beri margin.
  STOCK_STALE_AFTER   = 90.minutes
  # Solid Queue processes heartbeat roughly every 30-60s.
  WORKER_STALE_AFTER  = 5.minutes
  # price/paper jobs finish every few minutes, so silence here means trouble.
  JOB_ACTIVITY_WINDOW = 15.minutes

  Result = Struct.new(:checks, keyword_init: true) do
    def healthy?
      checks.values.all? { |c| c[:ok] }
    end

    def degraded
      checks.reject { |_, c| c[:ok] }.keys
    end
  end

  def self.run
    new.run
  end

  def run
    checks = {
      database:      database_check,
      job_activity:  job_activity_check,
      queue_workers: queue_workers_check
    }
    # Cek kesegaran data untuk aset yang aktif saja.
    if CRYPTO_ENABLED
      checks[:crypto_freshness] = crypto_freshness_check
    else
      checks[:stock_freshness] = stock_freshness_check
    end
    Result.new(checks: checks)
  end

  private

  def database_check
    ActiveRecord::Base.connection.select_value("SELECT 1")
    { ok: true, detail: "reachable" }
  rescue StandardError => e
    { ok: false, detail: "#{e.class}: #{e.message}" }
  end

  def job_activity_check
    last = SolidQueue::Job.where.not(finished_at: nil).maximum(:finished_at)
    age  = last && (Time.current - last)
    {
      ok: age.present? && age <= JOB_ACTIVITY_WINDOW,
      detail: last ? "last job finished #{age.round}s ago" : "no finished jobs yet"
    }
  rescue StandardError => e
    { ok: false, detail: "#{e.class}: #{e.message}" }
  end

  def queue_workers_check
    kinds = SolidQueue::Process.where(last_heartbeat_at: WORKER_STALE_AFTER.ago..)
                               .distinct.pluck(:kind)
    {
      ok: kinds.include?("Scheduler") && kinds.include?("Worker"),
      detail: "fresh: #{kinds.sort.join(', ').presence || 'none'}"
    }
  rescue StandardError => e
    { ok: false, detail: "#{e.class}: #{e.message}" }
  end

  def crypto_freshness_check
    latest = Candle.where(asset_type: "crypto", timeframe: "5m").maximum(:opened_at)
    age    = latest && (Time.current - latest)
    {
      ok: age.present? && age <= CRYPTO_STALE_AFTER,
      detail: latest ? "latest 5m candle #{age.round}s old" : "no crypto candles"
    }
  end

  # Saham cuma update saat market buka; kalau tutup, data basi itu normal (ok).
  def stock_freshness_check
    return { ok: true, detail: "market closed" } unless IdxMarket.open_now?

    latest = Candle.where(asset_type: "stock", timeframe: "1h").maximum(:opened_at)
    age    = latest && (Time.current - latest)
    {
      ok: age.present? && age <= STOCK_STALE_AFTER,
      detail: latest ? "latest 1h candle #{age.round}s old" : "no stock candles"
    }
  end
end
