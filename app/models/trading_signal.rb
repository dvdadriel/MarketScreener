class TradingSignal < ApplicationRecord
  self.table_name = "signals"

  has_many :paper_trades, dependent: :destroy

  after_create :create_paper_trade

  validates :symbol, :strategy, :fired_at, presence: true
  validates :signal_type, inclusion: { in: %w[BUY SELL NEUTRAL] }, allow_nil: true
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :recent,     -> { order(fired_at: :desc) }
  scope :unalerted,  -> { where(alerted: false) }
  scope :high_score, -> { where("score >= 0.7") }
  scope :buys,       -> { where(signal_type: "BUY") }
  scope :sells,      -> { where(signal_type: "SELL") }

  def badge_color
    case signal_type
    when "BUY"     then "bg-green-500 text-white"
    when "SELL"    then "bg-red-500 text-white"
    when "NEUTRAL" then "bg-gray-400 text-white"
    else "bg-gray-300 text-gray-700"
    end
  end

  def score_pct
    return 0 unless score
    (score * 100).round
  end

  private

  def create_paper_trade
    return if signal_type == "NEUTRAL"

    # Prefer ATR-based level from confluence service if present
    meta  = metadata || {}
    entry = meta["entry_price"]&.to_f || latest_close_price
    return unless entry

    rules    = PaperTrade.rules_for(self)
    sl_pct   = meta["sl_pct"]&.to_f || rules[:sl_pct]
    tp_pct   = meta["tp_pct"]&.to_f&.abs || rules[:tp_pct]

    paper_trades.create!(
      symbol:      symbol,
      asset_type:  asset_type,
      side:        signal_type,
      strategy:    strategy,
      timeframe:   meta["timeframe"] || meta[:timeframe],
      entry_price: entry,
      entry_at:    fired_at,
      current_price: entry,
      last_updated_at: fired_at,
      current_pnl_pct: 0,
      max_gain_pct: 0,
      max_loss_pct: 0,
      sl_pct:      sl_pct,
      tp_pct:      tp_pct,
      max_hours:   rules[:max_hours],
      status:      "open"
    )
  rescue => e
    Rails.logger.error("[TradingSignal#create_paper_trade] #{e.message}")
  end

  def latest_close_price
    tf = metadata&.dig("timeframe") || metadata&.dig(:timeframe) || "1h"
    # For confluence signals (timeframe = "multi"), use 1h as proxy for entry price
    tf = asset_type == "stock" ? "1d" : "1h" if tf == "multi"

    Candle.for_asset(asset_type)
          .for_symbol(symbol)
          .for_timeframe(tf)
          .order(opened_at: :desc)
          .limit(1)
          .pick(:close)
  end
end
