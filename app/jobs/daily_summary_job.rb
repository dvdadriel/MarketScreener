class DailySummaryJob < ApplicationJob
  queue_as :default

  def perform
    asset_types = CRYPTO_ENABLED ? %w[crypto stock] : %w[stock]
    asset_types.each do |asset_type|
      summary = build_summary(asset_type)
      next if summary.nil?

      notifier = TelegramNotifier.new(asset_type: asset_type)
      next unless notifier.send(:configured?)

      message = format_message(asset_type, summary)
      notifier.send(:post_message, message)
    end
  rescue => e
    Rails.logger.error("[DailySummaryJob] #{e.class}: #{e.message}")
  end

  private

  def build_summary(asset_type)
    today_window = 24.hours.ago..Time.current

    signals = TradingSignal.where(asset_type: asset_type, fired_at: today_window)
    return nil if signals.empty? && PaperTrade.where(asset_type: asset_type).where(entry_at: today_window).empty?

    closed_today = PaperTrade.where(asset_type: asset_type, status: "closed").where(exit_at: today_window)
    open_active  = PaperTrade.where(asset_type: asset_type, status: "open")

    overall = PaperTradeStats.for(asset_type)

    {
      signals_count: signals.count,
      signals_buy:   signals.where(signal_type: "BUY").count,
      signals_sell:  signals.where(signal_type: "SELL").count,
      open_trades:   open_active.count,
      closed_today:  closed_today.count,
      winners_today: closed_today.where("pnl_pct > 0").count,
      losers_today:  closed_today.where("pnl_pct <= 0").count,
      pnl_today:     closed_today.sum(:pnl_pct).to_f.round(2),
      best_today:    closed_today.order(pnl_pct: :desc).first,
      worst_today:   closed_today.order(pnl_pct: :asc).first,
      overall_wr:    overall[:win_rate],
      overall_avg:   overall[:avg_pnl],
      overall_total: overall[:total_closed]
    }
  end

  def format_message(asset_type, s)
    emoji  = asset_type == "stock" ? "🇮🇩" : "💰"
    label  = asset_type == "stock" ? "IDX" : "CRYPTO"
    date   = Time.current.in_time_zone(IdxMarket::TZ).strftime("%d %b %Y")
    today_pnl_color = s[:pnl_today] >= 0 ? "🟢" : "🔴"
    today_pnl_sign  = s[:pnl_today] >= 0 ? "+" : ""

    lines = [
      "#{emoji} *Daily Summary — #{label}*",
      "_#{date}_",
      "",
      "*📡 Signals today*",
      "  Total: #{s[:signals_count]} (#{s[:signals_buy]} BUY · #{s[:signals_sell]} SELL)",
      "",
      "*💼 Paper Trades*",
      "  Open active: `#{s[:open_trades]}`",
      "  Closed today: `#{s[:closed_today]}` (#{s[:winners_today]}W / #{s[:losers_today]}L)",
      "  Today P&L: #{today_pnl_color} *#{today_pnl_sign}#{s[:pnl_today]}%*"
    ]

    if s[:best_today]
      bt = s[:best_today]
      sym = format_sym(bt.symbol, asset_type)
      lines << "  🏆 Best:  `#{sym}` *+#{bt.pnl_pct.to_f.round(2)}%*"
    end
    if s[:worst_today] && s[:worst_today] != s[:best_today]
      wt = s[:worst_today]
      sym = format_sym(wt.symbol, asset_type)
      lines << "  💩 Worst: `#{sym}` *#{wt.pnl_pct.to_f.round(2)}%*"
    end

    lines << ""
    lines << "*📊 Overall (all-time)*"
    lines << "  Total closed: `#{s[:overall_total]}` trades"
    lines << "  Win rate: *#{s[:overall_wr]}%*"
    lines << "  Avg P&L: *#{s[:overall_avg] >= 0 ? "+" : ""}#{s[:overall_avg]}%*"

    lines.concat(momentum_lines) if asset_type == "stock"

    # Verdict
    lines << ""
    lines << if s[:overall_total] < 30
      "_📊 Sample masih kecil (<30 closed), tunggu data lebih banyak untuk evaluasi reliable._"
    elsif s[:overall_wr] >= 55 && s[:overall_avg] > 0
      "✅ *Sistem profitable* — pertahankan."
    elsif s[:overall_wr] < 40 || s[:overall_avg] < -1
      "⚠️ *Sistem underperform* — perlu tuning threshold."
    else
      "🟡 Performa borderline — terus monitor."
    end

    lines.join("\n")
  end

  def format_sym(sym, asset_type)
    asset_type == "stock" ? sym.sub(".JK", "") : sym
  end

  # Seksi momentum (strategi dalam observasi) — dari snapshot hari ini + tracker.
  def momentum_lines
    r = MomentumPaperTracker.new.call
    return [] if r[:tracked_days].zero?

    alpha = r[:ihsg_return] ? (r[:total_return] - r[:ihsg_return]).round(2) : nil
    picks = MomentumSnapshot.for_date(r[:as_of]).picks.order(:rank).pluck(:symbol)
    [ "",
      "*🚀 Momentum (observasi)*",
      "  Regime: `#{r[:regime_today]}` · #{picks.any? ? picks.map { |s| s.sub('.JK', '') }.join(', ') : 'CASH'}",
      "  Paper: #{r[:total_return] >= 0 ? '+' : ''}#{r[:total_return]}% · Alpha vs IHSG: #{alpha ? format('%+.2f%%', alpha) : '-'}" ]
  rescue => e
    Rails.logger.warn("[DailySummaryJob] momentum section: #{e.message}")
    []
  end
end
