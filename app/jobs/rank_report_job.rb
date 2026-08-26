# Laporan momentum harian ke Telegram (jadwal di recurring.yml).
#
# Kirim HANYA kalau komposisi top-10 berubah dari kiriman terakhir: momentum 6-1
# dihitung dari return 6 bulan, daftarnya nyaris tak berubah harian — pesan identik
# tiap jam = berhenti dibaca. Pick yang BARU masuk dikirim sebagai kartu lengkap
# (skor indikator + entry/SL/TP ATR), format sama dengan alert confluence lama.
#
# Risk-off tetap dikirim (permintaan eksplisit) — ditandai watchlist di header,
# karena ranking-nya informasi, bukan izin beli. Gate regime tetap berlaku di
# jalur aksi nyata (MomentumSnapshotJob / paper).
class RankReportJob < ApplicationJob
  queue_as :default

  LAST_KEY = "rank_report:last_picks".freeze

  def perform(universe = "extended")
    symbols = TelegramCommandService::UNIVERSES[universe.to_s]&.call
    return Rails.logger.warn("[RankReportJob] universe tak dikenal: #{universe}") unless symbols

    blocked = IdxMarketState.long_blocked?
    picks   = MomentumRankingService.new(symbols: symbols, ignore_regime: blocked).call
    return if picks.empty?

    current = picks.map { |p| p[:symbol] }
    last    = Array(Rails.cache.read(LAST_KEY))
    return if current == last   # komposisi sama → diam

    notifier = TelegramNotifier.new(asset_type: "stock")
    notifier.send_text(TelegramCommandService.format_rank(picks, blocked))
    picks.reject { |p| last.include?(p[:symbol]) }.each { |p| notifier.send_signal(card(p)) }

    Rails.cache.write(LAST_KEY, current)
  end

  private

  # TradingSignal TIDAK disimpan — cuma wadah supaya TelegramNotifier#format_message
  # bisa dipakai apa adanya (satu format kartu untuk semua alert).
  def card(pick)
    d = SignalConfluenceService.new(symbol: pick[:symbol], asset_type: "stock").detail("BUY")
    TradingSignal.new(
      symbol: pick[:symbol], asset_type: "stock", signal_type: "BUY",
      strategy: "MOMENTUM_RANK", fired_at: Time.current,
      score: d&.dig(:score), metadata: (d&.dig(:metadata) || {})
    )
  end
end
