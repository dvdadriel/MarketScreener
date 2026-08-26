require "test_helper"
require "zlib"

class EvidenceBackupServiceTest < ActiveSupport::TestCase
  # Folder terisolasi PER TEST (bukan BACKUP_DIR produksi) — hindari bentrok antar
  # worker paralel & jangan menulis ke lokasi backup nyata saat test.
  def setup
    @dir = Rails.root.join("tmp", "test_backups_#{Process.pid}_#{object_id}")
    # Bin palsu untuk mem-stub pg_dump/gzip. DI LUAR @dir supaya tidak tercampur
    # saat kita meng-assert isi direktori backup.
    @bin = Rails.root.join("tmp", "test_backups_bin_#{Process.pid}_#{object_id}")
  end

  def teardown
    FileUtils.rm_rf(@dir)
    FileUtils.rm_rf(@bin)
  end

  # Taruh executable palsu di depan PATH (mis. gzip yang gagal setelah membuat
  # output). Bentuk shell script, bukan stub Ruby: yang diuji justru batas
  # proses — exit status & sisa file di disk.
  def with_fake_bin(name, script)
    FileUtils.mkdir_p(@bin)
    path = @bin.join(name)
    File.write(path, script)
    File.chmod(0o755, path)
    orig = ENV["PATH"]
    ENV["PATH"] = "#{@bin}:#{orig}"
    yield
  ensure
    ENV["PATH"] = orig
  end

  test "dumps all evidence tables and reports success" do
    r = EvidenceBackupService.new(dir: @dir).call
    assert r.success?, "expected all tables to dump, failed: #{r.failed_tables}"
    assert_equal EvidenceBackupService::TABLES.sort, r.ok_tables.sort
    EvidenceBackupService::TABLES.each do |t|
      files = Dir.glob(@dir.join("#{t}-*.sql.gz"))
      assert files.any?, "no dump file for #{t}"

      # JANGAN cukup cek size.positive? — gzip dari input kosong = 20 byte dan
      # lolos asersi itu. Yang membuktikan backup nyata adalah ISI-nya: buka gzip
      # dan cari DDL/data tabelnya. Asersi lemah inilah yang meloloskan bug
      # "pg_dump gagal tapi dilaporkan sukses".
      sql = Zlib::GzipReader.open(files.first, &:read)
      assert_includes sql, t, "dump #{t} tidak menyebut nama tabelnya"
      assert_match(/CREATE TABLE|COPY /, sql,
                   "dump #{t} tanpa CREATE TABLE/COPY = bukan dump nyata")
    end
  end

  # Kegagalan pg_dump HARUS terlihat: tanpa ini Result#success? tetap true,
  # EvidenceBackupJob#alert_failure tak pernah jalan, dan file 20-byte menumpuk
  # sementara log tetap hijau — kelas silent failure yang justru diburu HealthCheck.
  test "reports failure when pg_dump cannot connect" do
    svc = EvidenceBackupService.new(dir: @dir)
    svc.define_singleton_method(:database) { "no_such_db_xyz" }

    r = svc.call
    refute r.success?, "pg_dump ke database bogus harus dilaporkan GAGAL"
    assert_equal EvidenceBackupService::TABLES.sort, r.failed_tables.sort
    assert_empty r.ok_tables
    assert_empty Dir.glob(@dir.join("*.sql.gz")),
                 "dump gagal tidak boleh meninggalkan arsip (mis. gzip kosong 20 byte)"
  end

  # gzip yang gagal SETELAH membuat outputnya meninggalkan <tabel>-<tgl>.sql.part.gz.
  # Itu gzip yang valid & mudah disalahsangka sebagai backup nyata saat audit, dan
  # rotate! meng-glob "*.sql.gz" yang TIDAK cocok dengan ".sql.part.gz"
  # (File.fnmatch("*.sql.gz", "x.sql.part.gz") == false) — jadi sampahnya menumpuk
  # SELAMANYA, satu per tabel gagal per hari.
  test "failed gzip leaves no partial archive behind" do
    script = <<~SH
      #!/bin/sh
      touch "$2.gz"    # gzip sempat membuat output...
      exit 1           # ...lalu gagal
    SH

    r = with_fake_bin("gzip", script) { EvidenceBackupService.new(dir: @dir).call }

    refute r.success?, "gzip gagal harus dilaporkan GAGAL"
    assert_equal EvidenceBackupService::TABLES.sort, r.failed_tables.sort
    assert_empty Dir.glob(@dir.join("*.part*")),
                 "sisa .part/.part.gz tidak boleh ditinggal — rotate! tak akan pernah menyapunya"
    assert_empty Dir.glob(@dir.join("*.sql.gz")), "tak boleh ada arsip dari dump gagal"
  end

  # pg_dump WAJIB dijalankan dengan -w (never prompt). pg_env membuang PGPASSWORD
  # saat env var passwordnya kosong — bentuk produksi yang normal — dan tanpa -w
  # pg_dump lalu MEMINTA password. Dengan tty di stdin (rake task, rails console,
  # worker di tmux) backup harian menggantung selamanya, bukan gagal: alertnya
  # tak pernah berbunyi dan job-nya diam-diam menahan slot antrian.
  test "runs pg_dump with -w so it can never block on a password prompt" do
    argv_log = @bin.join("pg_dump_argv")
    script   = <<~SH
      #!/bin/sh
      printf '%s\\n' "$@" > "#{argv_log}"
      exit 1
    SH

    with_fake_bin("pg_dump", script) { EvidenceBackupService.new(dir: @dir).call }

    argv = File.read(argv_log).lines.map(&:chomp)
    assert_includes argv, "-w", "pg_dump harus dipanggil dengan -w (never prompt)"
  end

  # Alert Telegram sengaja terse ("Backup bukti gagal: signals"), jadi LOG-lah
  # satu-satunya tempat operator bisa membedakan auth gagal / tabel hilang / disk
  # penuh. Membuang stderr pg_dump ke /dev/null membuat diagnosa jam 5 pagi
  # mustahil — rescue Ruby tak pernah melihat diagnosis pg_dump sendiri.
  test "logs pg_dump stderr when the dump fails" do
    io   = StringIO.new
    orig = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    svc = EvidenceBackupService.new(dir: @dir)
    svc.define_singleton_method(:database) { "no_such_db_xyz" }
    refute svc.call.success?

    assert_match(/no_such_db_xyz/, io.string,
                 "stderr pg_dump harus masuk log, bukan /dev/null")
  ensure
    Rails.logger = orig
  end

  test "rotates dumps older than retention window" do
    FileUtils.mkdir_p(@dir)
    old = @dir.join("momentum_snapshots-2020-01-01.sql.gz")
    File.write(old, "stale")
    stale_at = 40.days.ago.to_time
    File.utime(stale_at, stale_at, old)

    r = EvidenceBackupService.new(dir: @dir).call
    assert_equal 1, r.removed_count
    refute File.exist?(old)
  end
end
