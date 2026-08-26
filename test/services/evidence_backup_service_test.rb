require "test_helper"

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
      assert File.size(files.first).positive?
    end
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
