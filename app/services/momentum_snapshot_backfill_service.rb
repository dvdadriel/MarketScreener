# Isi hari bursa yang bolong (plan H3) — mis. Mac tidur/mati saat jadwal 17:00 WIB,
# atau data sempat basi (lihat guard H4 di MomentumSnapshotJob). Pakai ranking as-of
# (tanpa lookahead, memakai candle yang SUDAH tersimpan) — akurat, bukan tebakan.
# Dipanggil di awal MomentumSnapshotJob tiap run; idempotent (skip hari yang sudah ada).
class MomentumSnapshotBackfillService
  MAX_BACKFILL_DAYS = 60   # gap lebih lama = butuh investigasi manual, bukan auto-fill

  # Mengembalikan jumlah hari yang BERHASIL tercatat, bukan yang dicoba.
  # backfill_day sengaja menelan exception (satu hari rusak tak boleh
  # menjatuhkan sisanya), jadi menghitung days.size akan melaporkan sukses
  # meski nol hari benar-benar tercatat — dan kontinuitas bukti justru hal
  # yang service ini jaga.
  def call
    days     = missing_trading_days
    recorded = days.count { |d| backfill_day(d) }

    if recorded < days.size
      Rails.logger.warn("[MomentumSnapshotBackfillService] #{days.size - recorded}/#{days.size} hari GAGAL di-backfill — bukti berlubang, lihat log error di atas")
    end

    recorded
  end

  private

  def missing_trading_days
    last = MomentumSnapshot.snapshot_dates.last
    return [] unless last   # belum pernah ada snapshot: mulai fresh, jangan reka histori

    today = Time.current.in_time_zone(IdxMarket::TZ).to_date
    gap = trading_dates.select { |d| d > last && d < today }
    if gap.size > MAX_BACKFILL_DAYS
      Rails.logger.warn("[MomentumSnapshotBackfillService] gap #{gap.size} hari > cap #{MAX_BACKFILL_DAYS}, ambil #{MAX_BACKFILL_DAYS} terakhir")
      gap = gap.last(MAX_BACKFILL_DAYS)
    end
    gap
  end

  def trading_dates
    Candle.where(asset_type: "index", symbol: IdxMarketState::SYMBOL, timeframe: "1d")
          .order(:opened_at).pluck(:opened_at).map(&:to_date).uniq
  end

  def backfill_day(date)
    as_of = date.in_time_zone(IdxMarket::TZ).end_of_day
    Thread.current[:backtest_as_of] = as_of

    picks  = MomentumRankingService.new(as_of: as_of).call
    regime = picks.empty? && IdxMarketState.long_blocked? ? "risk_off" : "risk_on"
    MomentumSnapshot.record!(date: date, picks: picks, regime: regime)

    Rails.logger.info("[MomentumSnapshotBackfillService] backfilled #{date}: #{regime}, #{picks.size} picks")
    true
  rescue => e
    Rails.logger.error("[MomentumSnapshotBackfillService] #{date}: #{e.class}: #{e.message}")
    false
  ensure
    # ensure TIDAK mengubah nilai kembalian selama tak ada `return` eksplisit —
    # jadi true/false di atas tetap yang dilaporkan ke `call`.
    Thread.current[:backtest_as_of] = nil
  end
end
