class HealthMonitorJob < ApplicationJob
  queue_as :default

  # Only these checks page a human — db/job_activity problems also surface here
  # but freshness + dead workers are the "silent stop" signals worth alerting on.
  # Freshness key mengikuti aset aktif (crypto_freshness saat crypto on, else stock_freshness);
  # slice mengabaikan key yang tak ada, jadi aman mencantumkan keduanya.
  MONITORED = %i[crypto_freshness stock_freshness queue_workers].freeze
  ALERT_COOLDOWN = 30.minutes
  LAST_ALERT_KEY = "health_monitor:last_alert_at".freeze
  DEGRADED_KEY   = "health_monitor:degraded".freeze

  def perform
    failing = HealthCheck.run.checks.slice(*MONITORED).reject { |_, c| c[:ok] }

    if failing.any?
      handle_degraded(failing)
    else
      handle_recovered
    end
  end

  private

  def handle_degraded(failing)
    Rails.logger.warn("[HealthMonitorJob] degraded: #{failing.keys.join(', ')}")

    last = Rails.cache.read(LAST_ALERT_KEY)
    Rails.cache.write(DEGRADED_KEY, true, expires_in: 1.day)
    return if last && (Time.current.to_i - last) < ALERT_COOLDOWN.to_i

    lines = [ "🩺 *CryptoRadar health degraded*", "" ]
    failing.each { |name, c| lines << "• `#{name}` — #{c[:detail]}" }

    if send_telegram(lines.join("\n"))
      Rails.cache.write(LAST_ALERT_KEY, Time.current.to_i, expires_in: 1.day)
    end
  end

  def handle_recovered
    return unless Rails.cache.read(DEGRADED_KEY)

    send_telegram("✅ *CryptoRadar recovered* — all health checks passing")
    Rails.cache.delete(DEGRADED_KEY)
    Rails.cache.delete(LAST_ALERT_KEY)
  end

  def send_telegram(text)
    # Alert operasional (bukan trading) — pakai bot stock yang aktif.
    notifier = TelegramNotifier.new(asset_type: "stock")
    return false unless notifier.send(:configured?)

    notifier.send(:post_message, text)
    true
  rescue StandardError => e
    Rails.logger.error("[HealthMonitorJob] alert failed: #{e.message}")
    false
  end
end
