namespace :backup do
  desc "Backup tabel bukti (momentum_snapshots, paper_trades, trading_signals) + rotasi 30 hari"
  task evidence: :environment do
    r = EvidenceBackupService.new.call
    r.ok_tables.each { |t| puts "OK   #{t}" }
    r.failed_tables.each { |t| puts "FAIL #{t}" }
    puts "Rotasi: #{r.removed_count} file lama dihapus (> #{EvidenceBackupService::RETENTION_DAYS} hari)"
    raise "Backup gagal untuk: #{r.failed_tables.join(', ')}" unless r.success?
  end
end
