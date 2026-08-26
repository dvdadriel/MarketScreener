require "test_helper"
require "zlib"

class EvidenceBackupServiceTest < ActiveSupport::TestCase
  # Folder terisolasi PER TEST (bukan BACKUP_DIR produksi) — hindari bentrok antar
  # worker paralel & jangan menulis ke lokasi backup nyata saat test.
  def setup
    @dir = Rails.root.join("tmp", "test_backups_#{Process.pid}_#{object_id}")
  end

  def teardown
    FileUtils.rm_rf(@dir)
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
