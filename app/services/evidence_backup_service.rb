require "open3"

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

    # -w = never prompt. pg_env membuang PGPASSWORD kalau env var-nya kosong (bentuk
    # produksi yang normal), dan tanpa -w pg_dump lalu MEMINTA password: dengan tty
    # di stdin (rake, rails console, worker di tmux) backup harian menggantung
    # selamanya alih-alih gagal, jadi alertnya tak pernah berbunyi.
    ok, err = run(pg_env, "pg_dump", "-w", "-t", table, "-d", db, "-f", raw.to_s)
    return log_failure(table, "pg_dump", err) unless ok

    size = File.size?(raw).to_i
    return log_failure(table, "pg_dump", "output #{size} byte <= MIN_DUMP_BYTES") unless size > MIN_DUMP_BYTES

    ok, err = run({}, "gzip", "-f", raw.to_s)
    return log_failure(table, "gzip", err) unless ok

    File.rename("#{raw}.gz", out)
    true
  rescue => e
    Rails.logger.error("[EvidenceBackupService] #{table}: #{e.class}: #{e.message}")
    false
  ensure
    # Sisa dump gagal/parsial jangan ditinggal: menyesatkan saat audit bukti.
    # KEDUA jejaknya harus disapu — .part DAN .part.gz. gzip yang gagal setelah
    # membuat outputnya (atau File.rename yang meledak) meninggalkan .part.gz:
    # gzip valid yang mudah disalahsangka backup nyata, dan rotate! meng-glob
    # "*.sql.gz" yang TIDAK cocok dengan ".sql.part.gz" — jadi tanpa ini sampahnya
    # menumpuk selamanya. Setelah rename sukses tak ada satupun dari keduanya
    # tersisa, jadi pembersihan tanpa syarat ini aman.
    [ raw, "#{raw}.gz" ].each { |f| File.delete(f) if f && File.exist?(f) } if raw
  end

  # Open3, bukan system+err: File::NULL: stderr perlu DITANGKAP, bukan dibuang.
  # stdout memang tak dipakai (pg_dump menulis ke -f, gzip ke file), tapi tetap
  # ditangkap supaya tak pernah bocor ke log job.
  def run(env, *argv)
    _out, err, status = Open3.capture3(env, *argv)
    [ status.success?, err ]
  end

  # Pesan Telegram sengaja terse, jadi LOG-lah satu-satunya tempat operator bisa
  # membedakan auth ditolak / tabel hilang / disk penuh. Baris pertama stderr
  # sudah memuat diagnosis pg_dump; sisanya jarang menambah informasi.
  def log_failure(table, step, detail)
    first = detail.to_s.lines.first&.strip
    Rails.logger.error("[EvidenceBackupService] #{table}: #{step} gagal#{" — #{first}" if first.present?}")
    false
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
