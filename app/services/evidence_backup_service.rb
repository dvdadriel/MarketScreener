# Backup harian tabel bukti forward-tracking (plan H2). Tabel ini adalah dasar
# keputusan gate promosi 8 minggu (§1.3) — kehilangannya berarti mulai dari nol.
# Dump plain SQL + gzip (bisa diperiksa manual), rotasi RETENTION_DAYS.
class EvidenceBackupService
  TABLES          = %w[momentum_snapshots paper_trades trading_signals].freeze
  RETENTION_DAYS  = 30
  BACKUP_DIR      = Rails.root.join("storage", "db_backups")

  Result = Struct.new(:ok_tables, :failed_tables, :removed_count, keyword_init: true) do
    def success? = failed_tables.empty?
  end

  # dir: override lokasi (test pakai folder terisolasi — jangan tulis ke backup
  # produksi & jangan bentrok antar worker paralel yang berbagi BACKUP_DIR).
  def initialize(dir: BACKUP_DIR)
    @dir = dir
  end

  def call
    FileUtils.mkdir_p(@dir)
    db   = ActiveRecord::Base.connection_db_config.database
    date = Time.current.in_time_zone(IdxMarket::TZ).strftime("%Y-%m-%d")

    ok, failed = TABLES.partition { |t| dump_table(t, db, date) }
    removed = rotate!

    Result.new(ok_tables: ok, failed_tables: failed, removed_count: removed)
  end

  private

  def dump_table(table, db, date)
    out = @dir.join("#{table}-#{date}.sql.gz")
    system("pg_dump -t #{table} #{db} | gzip > #{out}", out: File::NULL, err: File::NULL) &&
      File.size?(out).to_i.positive?
  rescue => e
    Rails.logger.error("[EvidenceBackupService] #{table}: #{e.class}: #{e.message}")
    false
  end

  def rotate!
    cutoff = RETENTION_DAYS.days.ago
    Dir.glob(@dir.join("*.sql.gz")).count do |f|
      next false unless File.mtime(f) < cutoff
      File.delete(f)
      true
    end
  end
end
