class PaperTrade < ApplicationRecord
  belongs_to :trading_signal

  scope :open_trades,   -> { where(status: "open") }
  scope :closed_trades, -> { where(status: "closed") }
  scope :winners,       -> { closed_trades.where("pnl_pct > 0") }
  scope :losers,        -> { closed_trades.where("pnl_pct <= 0") }

  # Auto-close rules (SL/TP/time limit) keyed by timeframe / strategy.
  RULES = {
    scalp:   { sl_pct: -2.0,  tp_pct: 3.0,  max_hours: 4 },
    swing:   { sl_pct: -5.0,  tp_pct: 10.0, max_hours: 168 },     # 7 days
    daily:   { sl_pct: -8.0,  tp_pct: 15.0, max_hours: 336 }      # 14 days (SWING_PICK)
  }.freeze

  SCALP_TIMEFRAMES = %w[5m 15m].freeze

  def self.rules_for(signal)
    return RULES[:daily] if signal.strategy == "SWING_PICK"

    tf = signal.metadata&.dig("timeframe") || signal.metadata&.dig(:timeframe)
    SCALP_TIMEFRAMES.include?(tf) ? RULES[:scalp] : RULES[:swing]
  end

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def winner?
    pnl_pct.to_f > 0
  end

  def pnl_color
    val = (closed? ? pnl_pct : current_pnl_pct).to_f
    if val > 0
      "text-green-400"
    elsif val < 0
      "text-red-400"
    else
      "text-gray-400"
    end
  end
end
