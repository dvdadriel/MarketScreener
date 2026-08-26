# Laporan rekonsiliasi mingguan (plan 1.2): momentum paper vs IHSG vs ekspektasi
# backtest, plus kontrol negatif (confluence yang di-mute). Trust loop: mendeteksi
# drift/edge-decay lebih awal, dan mengumpulkan bukti untuk gate promosi (§1.3).
class MomentumWeeklyReportJob < ApplicationJob
  queue_as :default

  # Referensi backtest tervalidasi (LQ45, 4 window 2022-2026, fee+regime):
  # alpha tahunan +1.4%..+21.2%, maxDD 2-7%. Dipakai sebagai garis ekspektasi.
  BACKTEST_ALPHA_NOTE = "+1,4%..+21,2%/thn (LQ45 4 window)".freeze

  def perform
    r = MomentumPaperTracker.new.call
    if r[:tracked_days].zero?
      Rails.logger.info("[MomentumWeeklyReportJob] belum ada snapshot — skip")
      return
    end

    notifier = TelegramNotifier.new(asset_type: "stock")
    return unless notifier.send(:configured?)

    notifier.send(:post_message, build_message(r))
  end

  private

  def build_message(r)
    week_mom  = weekly_return(r[:equity_curve])
    week_ihsg = weekly_ihsg
    alpha_cum = r[:ihsg_return] ? (r[:total_return] - r[:ihsg_return]).round(2) : nil

    lines = [ "📊 *Rekonsiliasi Mingguan Momentum*", "" ]
    lines << "*Minggu ini:* momentum #{fmt(week_mom)} vs IHSG #{fmt(week_ihsg)}"
    lines << "*Sejak #{r[:inception]}* (#{r[:tracked_days]} hari):"
    lines << "  Paper: #{fmt(r[:total_return])} · maxDD -#{r[:max_drawdown]}%"
    lines << "  IHSG:  #{fmt(r[:ihsg_return])} · Alpha: *#{fmt(alpha_cum)}*"
    lines << "  Regime: `#{r[:regime_today]}` · Holdings: #{r[:holdings].any? ? r[:holdings].map { |s| s.sub('.JK', '') }.join(', ') : 'CASH'}"
    lines << ""
    lines << "*Vs backtest:* ekspektasi alpha #{BACKTEST_ALPHA_NOTE}"
    lines.concat(gate_progress_lines)
    lines << ""
    lines << negative_control_line
    lines.join("\n")
  end

  # Plan H6: verdict otomatis kriteria promosi §1.3 — tak menunggu penilaian manual.
  def gate_progress_lines
    v = MomentumGateEvaluator.new.call
    lines = [ "", "*🚦 Gate promosi:* minggu #{v.weeks_tracked}/#{v.weeks_required}" ]

    if v.evaluated
      lines << "  #{check(v.criteria[:duration])} Durasi ≥ #{v.weeks_required} minggu"
      lines << "  #{check(v.criteria[:alpha])} Alpha kumulatif > 0 (#{fmt(v.alpha_cumulative)})"
      lines << "  #{check(v.criteria[:drawdown])} maxDD ≤ #{v.max_dd_ceiling}% (#{v.max_drawdown}%)"
      lines << "  #{check(v.criteria[:regime])} Perilaku regime konsisten"
      lines << (v.promote ? "✅ *SEMUA KRITERIA TERPENUHI — siap dipromosikan*" : "⏸ Belum semua kriteria terpenuhi — lanjut observasi")
    else
      lines << "  _#{v.weeks_required - v.weeks_tracked} minggu lagi sebelum dinilai (kriteria lain baru bermakna setelah durasi cukup)_"
    end
    lines
  end

  def check(ok) = ok ? "✅" : "❌"

  # Kontrol negatif: confluence (dibungkam, terbukti rugi di backtest). Kalau ia
  # tiba-tiba profit forward, metodologi kita yang salah — bukan kabar baik.
  def negative_control_line
    rows = PaperTradeStats.for("stock")[:by_strategy]
             .select { |s| s[:strategy].to_s.start_with?("CONFLUENCE") }
    return "_Kontrol negatif (confluence): belum ada trade tertutup_" if rows.empty?

    total = rows.sum { |s| s[:total] }
    avg   = (rows.sum { |s| s[:avg_pnl] * s[:total] } / total).round(2)
    "_Kontrol negatif (confluence, muted): n=#{total}, avg #{fmt(avg)} — ekspektasi: negatif_"
  end

  def weekly_return(curve)
    return nil if curve.size < 2
    cutoff = curve.last[0] - 7
    base = curve.reverse_each.find { |d, _| d <= cutoff } || curve.first
    ((curve.last[1] / base[1] - 1.0) * 100).round(2)
  end

  def weekly_ihsg
    rows = Candle.where(asset_type: "index", symbol: IdxMarketState::SYMBOL, timeframe: "1d")
                 .where("opened_at >= ?", 9.days.ago).order(:opened_at).pluck(:close)
    return nil if rows.size < 2
    ((rows.last.to_f / rows.first.to_f - 1.0) * 100).round(2)
  end

  def fmt(v)
    v.nil? ? "-" : format("%+.2f%%", v)
  end
end
