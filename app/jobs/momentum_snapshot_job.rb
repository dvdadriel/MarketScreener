# Harian pasca-tutup IDX (setelah IdxScannerJob mengisi candle 1d): rekam regime +
# top-10 momentum ke momentum_snapshots. Ini pengumpul data forward-tracking —
# TIDAK mengirim alert & TIDAK membuka PaperTrade; equity dihitung on-the-fly oleh
# MomentumPaperTracker dari snapshot ini (satu sumber kebenaran, tanpa state ganda).
#
# H3: backfill hari bursa yang bolong (mis. Mac tidur) dijalankan lebih dulu tiap run.
# H4: kalau candle 1d terlambat > MAX_STALE_TRADING_DAYS hari bursa, jangan rekam hari
# ini (data basi akan mencemari bukti) — backfill run berikutnya akan mengisi begitu
# data pulih.
class MomentumSnapshotJob < ApplicationJob
  queue_as :default

  MAX_STALE_TRADING_DAYS = 2

  def perform
    MomentumSnapshotBackfillService.new.call

    date = Time.current.in_time_zone(IdxMarket::TZ).to_date
    return if MomentumSnapshot.taken_for?(date)   # idempotent (retry/restart aman)

    unless data_fresh_enough?
      Rails.logger.warn("[MomentumSnapshotJob] candle stock basi (>#{MAX_STALE_TRADING_DAYS} hari bursa) — skip #{date}, backfill akan mengisi setelah data pulih")
      return
    end

    picks  = MomentumRankingService.new.call
    regime = picks.empty? && IdxMarketState.long_blocked? ? "risk_off" : "risk_on"
    MomentumSnapshot.record!(date: date, picks: picks, regime: regime)

    Rails.logger.info("[MomentumSnapshotJob] #{date}: #{regime}, #{picks.size} picks")
  end

  private

  # Kesegaran diukur dalam HARI BURSA (via kalender ^JKSE), bukan hari kalender —
  # weekend/libur tak boleh dianggap "basi".
  def data_fresh_enough?
    latest = Candle.where(asset_type: "stock", timeframe: "1d").maximum(:opened_at)
    return false unless latest

    stale_trading_days = Candle.where(asset_type: "index", symbol: IdxMarketState::SYMBOL, timeframe: "1d")
                                .where("opened_at > ?", latest).count
    stale_trading_days <= MAX_STALE_TRADING_DAYS
  end
end
