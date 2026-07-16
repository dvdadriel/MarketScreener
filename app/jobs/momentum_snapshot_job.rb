# Harian pasca-tutup IDX (setelah IdxScannerJob mengisi candle 1d): rekam regime +
# top-10 momentum ke momentum_snapshots. Ini pengumpul data forward-tracking —
# TIDAK mengirim alert & TIDAK membuka PaperTrade; equity dihitung on-the-fly oleh
# MomentumPaperTracker dari snapshot ini (satu sumber kebenaran, tanpa state ganda).
class MomentumSnapshotJob < ApplicationJob
  queue_as :default

  def perform
    date = Time.current.in_time_zone(IdxMarket::TZ).to_date
    return if MomentumSnapshot.taken_for?(date)   # idempotent (retry/restart aman)

    picks  = MomentumRankingService.new.call
    regime = picks.empty? && IdxMarketState.long_blocked? ? "risk_off" : "risk_on"

    if picks.empty?
      MomentumSnapshot.create!(snapshot_date: date, regime: regime)
    else
      picks.each_with_index do |p, i|
        MomentumSnapshot.create!(
          snapshot_date: date, regime: regime, rank: i + 1,
          symbol: p[:symbol], momentum: p[:momentum], price: p[:last_close]
        )
      end
    end

    Rails.logger.info("[MomentumSnapshotJob] #{date}: #{regime}, #{picks.size} picks")
  end
end
