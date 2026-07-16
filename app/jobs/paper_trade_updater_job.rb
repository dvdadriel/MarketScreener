class PaperTradeUpdaterJob < ApplicationJob
  queue_as :default

  def perform
    PaperTrade.open_trades.find_each do |trade|
      update_trade(trade)
    rescue => e
      Rails.logger.error("[PaperTradeUpdaterJob] trade #{trade.id}: #{e.message}")
    end
  end

  private

  def update_trade(trade)
    latest = latest_price(trade)
    return unless latest

    entry = trade.entry_price.to_f
    pnl   = pnl_for_side(trade.side, entry, latest)

    trade.current_price    = latest
    trade.current_pnl_pct  = pnl
    trade.last_updated_at  = Time.current
    trade.max_gain_pct     = [ trade.max_gain_pct.to_f, pnl ].max
    trade.max_loss_pct     = [ trade.max_loss_pct.to_f, pnl ].min

    if (reason = exit_reason(trade, pnl))
      close_trade!(trade, latest, pnl, reason)
    else
      trade.save!
    end
  end

  def pnl_for_side(side, entry, current)
    raw = (current - entry) / entry * 100.0
    side == "SELL" ? -raw : raw   # SELL profits when price drops
  end

  def latest_price(trade)
    tf = trade.timeframe.presence || (trade.asset_type == "stock" ? "1d" : "1h")
    tf = trade.asset_type == "stock" ? "1d" : "1h" if tf == "multi"

    Candle.for_asset(trade.asset_type)
          .for_symbol(trade.symbol)
          .for_timeframe(tf)
          .order(opened_at: :desc)
          .limit(1)
          .pick(:close)
          &.to_f
  end

  def exit_reason(trade, pnl)
    return "take_profit" if pnl >= trade.tp_pct.to_f
    return "stop_loss"   if pnl <= trade.sl_pct.to_f

    if trade.max_hours
      hours_open = ((Time.current - trade.entry_at) / 3600).to_f
      return "time_limit" if hours_open >= trade.max_hours
    end

    nil
  end

  def close_trade!(trade, exit_price, pnl, reason)
    trade.update!(
      exit_price:  exit_price,
      exit_at:     Time.current,
      exit_reason: reason,
      pnl_pct:     pnl,
      status:      "closed"
    )
    Rails.logger.info("[PaperTrade] CLOSED #{trade.symbol} #{trade.side} reason=#{reason} pnl=#{pnl.round(2)}%")
  end
end
