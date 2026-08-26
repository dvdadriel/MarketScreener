# Backup harian tabel bukti (plan H2). Gagal → alert Telegram (bot stock, sama
# dengan alert operasional lain) — jangan biarkan kegagalan senyap.
class EvidenceBackupJob < ApplicationJob
  queue_as :default

  def perform
    r = EvidenceBackupService.new.call
    Rails.logger.info("[EvidenceBackupJob] ok=#{r.ok_tables.join(',')} failed=#{r.failed_tables.join(',')} removed=#{r.removed_count}")
    alert_failure(r) unless r.success?
  end

  private

  def alert_failure(r)
    TelegramNotifier.new(asset_type: "stock")
      .send_text("🚨 *Backup bukti gagal*: #{r.failed_tables.join(', ')} — cek storage/log.")
  end
end
