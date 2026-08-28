namespace :idx do
  desc "Refresh universe IDX (05:00 WIB) — dulu di config/recurring.yml"
  task universe_refresh: :environment do
    IdxUniverseService.refresh!
  end

  desc "Scan IDX, pilih top swing candidates (16:30 WIB)"
  task scanner: :environment do
    IdxScannerJob.perform_now
  end

  desc "Rekam regime + top-10 momentum harian, forward tracking (17:00 WIB)"
  task snapshot: :environment do
    MomentumSnapshotJob.perform_now
    DashboardSummaryMaterializer.new.call
  end

  desc "Laporan momentum harian + kartu BUY (17:15 WIB)"
  task rank_report: :environment do
    RankReportJob.perform_now("extended")
  end

  desc "Digest Telegram harian: sinyal, P&L, win rate (17:00 WIB)"
  task daily_summary: :environment do
    DailySummaryJob.perform_now
  end

  desc "Backup tabel bukti forward-tracking (18:45 WIB)"
  task evidence_backup: :environment do
    EvidenceBackupJob.perform_now
  end

  desc "Hapus candle lewat retensi per timeframe (10:15 WIB)"
  task candle_prune: :environment do
    CandlePruneJob.perform_now
  end

  desc "Laporan mingguan trust-loop momentum (Jumat 17:30 WIB)"
  task weekly_report: :environment do
    MomentumWeeklyReportJob.perform_now
  end

  desc "Poll candle IDX (tiap 30 menit, skip kalau market tutup)"
  task poll: :environment do
    StockPollerJob.perform_now
  end

  desc "Update paper trade terbuka (tiap 5 menit)"
  task paper_trade_update: :environment do
    PaperTradeUpdaterJob.perform_now
  end

  desc "Watchdog data stale / worker mati (tiap 5 menit)"
  task health_monitor: :environment do
    HealthMonitorJob.perform_now
  end

  desc "Alert Telegram untuk job gagal baru (tiap 15 menit)"
  task failed_job_alert: :environment do
    FailedJobAlertJob.perform_now
  end
end
