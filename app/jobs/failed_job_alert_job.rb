class FailedJobAlertJob < ApplicationJob
  queue_as :default

  # Surfaces Solid Queue failures (which otherwise sit silently in
  # solid_queue_failed_executions) to Telegram. Tracks the last alerted id in a
  # file so it survives process restarts and never double-alerts.
  STATE_FILE = Rails.root.join("tmp", "last_failed_job_alert_id.txt")
  MAX_PER_RUN = 10

  def perform
    last_id = read_last_id
    failures = SolidQueue::FailedExecution.includes(:job)
                                          .where("id > ?", last_id)
                                          .order(:id)
                                          .to_a
    return if failures.empty?

    # First run on a fresh state file: adopt the high-water mark without
    # blasting historical failures.
    if last_id.zero?
      write_last_id(failures.last.id)
      return
    end

    notify(failures.first(MAX_PER_RUN), total: failures.size)
    write_last_id(failures.last.id)
  end

  private

  def notify(failures, total:)
    # Alert operasional (bukan trading) — pakai bot stock yang aktif.
    notifier = TelegramNotifier.new(asset_type: "stock")
    return unless notifier.send(:configured?)

    lines = [ "🚨 *#{total} background job failure#{'s' if total > 1}*", "" ]
    failures.each do |f|
      klass = f.job&.class_name || "UnknownJob"
      first_line = f.error.to_s.lines.first.to_s.strip.truncate(160)
      lines << "• `#{klass}` — #{first_line}"
    end
    lines << "" << "_+ #{total - failures.size} more_" if total > failures.size

    notifier.send(:post_message, lines.join("\n"))
  rescue => e
    Rails.logger.error("[FailedJobAlertJob] notify failed: #{e.message}")
  end

  def read_last_id
    Integer(File.read(STATE_FILE).strip)
  rescue StandardError
    0
  end

  def write_last_id(id)
    File.write(STATE_FILE, id.to_s)
  rescue StandardError => e
    Rails.logger.error("[FailedJobAlertJob] could not persist state: #{e.message}")
  end
end
