# Backup harian tabel bukti forward-tracking (plan H2). Tabel ini adalah dasar
# keputusan gate promosi 8 minggu (§1.3) — kehilangannya berarti mulai dari nol.
# Dump plain SQL + gzip (bisa diperiksa manual), rotasi RETENTION_DAYS.
class EvidenceBackupService
  # Nama tabel diambil DARI MODEL, bukan ditulis ulang: versi hardcoded pernah
  # menyebut "trading_signals" padahal TradingSignal.table_name = "signals", jadi
  # tabel itu tak pernah ikut ter-backup (dan tetap dilaporkan sukses).
  TABLES          = [ MomentumSnapshot, PaperTrade, TradingSignal ].map(&:table_name).freeze
  RETENTION_DAYS  = 30
  BACKUP_DIR      = Rails.root.join("storage", "db_backups")
  # pg_dump plain satu tabel selalu jauh di atas ini (header + CREATE TABLE + COPY;
  # terukur ~2,8-4,5 KB). Ambangnya ada karena gzip dari input KOSONG = tepat 20
  # byte, sehingga cek "size > 0" lolos walau dump-nya gagal total.
  MIN_DUMP_BYTES  = 512

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
    db   = database
    date = Time.current.in_time_zone(IdxMarket::TZ).strftime("%Y-%m-%d")

    ok, failed = TABLES.partition { |t| dump_table(t, db, date) }
    removed = rotate!

    Result.new(ok_tables: ok, failed_tables: failed, removed_count: removed)
  end

  private

  # Dump lalu compress sebagai DUA langkah yang diperiksa TERPISAH. Versi lama
  # memakai satu pipeline shell (`pg_dump ... | gzip > out`): exit status yang
  # dikembalikan `system` adalah milik perintah TERAKHIR (gzip), jadi pg_dump yang
  # gagal — tabel tak ada, auth ditolak — tak pernah terlihat.
  # Bentuk argv (bukan string shell) sekaligus menutup interpolasi nama tabel ke
  # shell, sejalan dengan aturan "tidak ada eval/shell/interpolasi" di repo ini.
  def dump_table(table, db, date)
    out = @dir.join("#{table}-#{date}.sql.gz")
    raw = @dir.join("#{table}-#{date}.sql.part")

    ok = system(pg_env, "pg_dump", "-t", table, "-d", db, "-f", raw.to_s,
                out: File::NULL, err: File::NULL)
    return false unless ok && File.size?(raw).to_i > MIN_DUMP_BYTES
    return false unless system("gzip", "-f", raw.to_s, out: File::NULL, err: File::NULL)

    File.rename("#{raw}.gz", out)
    true
  rescue => e
    Rails.logger.error("[EvidenceBackupService] #{table}: #{e.class}: #{e.message}")
    false
  ensure
    # Sisa dump gagal/parsial jangan ditinggal: menyesatkan saat audit bukti.
    File.delete(raw) if raw && File.exist?(raw)
  end

  def db_config = ActiveRecord::Base.connection_db_config.configuration_hash

  def database = db_config[:database]

  # Kredensial koneksi diteruskan EKSPLISIT ke pg_dump. Versi lama hanya memakai
  # nama database, jadi di produksi (user non-default / host remote) pg_dump gagal
  # autentikasi. Key nil dibuang supaya trust auth lokal (tanpa host/user) tetap jalan.
  def pg_env
    {
      "PGHOST"     => db_config[:host],
      "PGPORT"     => db_config[:port]&.to_s,
      "PGUSER"     => db_config[:username],
      "PGPASSWORD" => db_config[:password]
    }.compact
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
