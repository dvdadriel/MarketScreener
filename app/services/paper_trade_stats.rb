class PaperTradeStats
  CACHE_TTL = 60.seconds

  # Cached: this runs several aggregate queries and is hit on every dashboard
  # render. A 60s window is fine — trades only change every few minutes, and the
  # version key busts the cache immediately when a trade is added or updated.
  def self.for(asset_type)
    scope = PaperTrade.where(asset_type: asset_type)
    version = scope.maximum(:updated_at)&.to_i
    Rails.cache.fetch([ "paper_trade_stats", asset_type, scope.count, version ], expires_in: CACHE_TTL) do
      new(asset_type).call
    end
  end

  def initialize(asset_type)
    @scope = PaperTrade.where(asset_type: asset_type)
  end

  def call
    closed = @scope.closed_trades
    open_t = @scope.open_trades

    total_closed = closed.count
    winners      = closed.winners.count
    losers       = closed.losers.count
    win_rate     = total_closed.zero? ? 0 : (winners.to_f / total_closed * 100).round(1)

    avg_pnl      = closed.average(:pnl_pct)&.to_f&.round(2) || 0.0
    avg_winner   = closed.winners.average(:pnl_pct)&.to_f&.round(2) || 0.0
    avg_loser    = closed.losers.average(:pnl_pct)&.to_f&.round(2) || 0.0

    # Risk metrics — per-trade pnl_pct, urut waktu exit untuk equity curve.
    pnls = closed.where.not(pnl_pct: nil).order(:exit_at).pluck(:pnl_pct).map(&:to_f)
    risk = RiskMetrics.compute(pnls)

    by_strategy  = closed.group(:strategy).pluck(
      :strategy,
      Arel.sql("COUNT(*)"),
      Arel.sql("SUM(CASE WHEN pnl_pct > 0 THEN 1 ELSE 0 END)"),
      Arel.sql("AVG(pnl_pct)")
    ).map { |strat, total, wins, avg|
      {
        strategy: strat,
        total:    total,
        wins:     wins,
        win_rate: total.zero? ? 0 : (wins.to_f / total * 100).round(1),
        avg_pnl:  avg.to_f.round(2)
      }
    }.sort_by { |s| -s[:avg_pnl] }

    {
      total_closed: total_closed,
      open_count:   open_t.count,
      winners:      winners,
      losers:       losers,
      win_rate:     win_rate,
      avg_pnl:      avg_pnl,
      avg_winner:   avg_winner,
      avg_loser:    avg_loser,
      best_trade:   closed.order(pnl_pct: :desc).first,
      worst_trade:  closed.order(pnl_pct: :asc).first,
      by_strategy:  by_strategy,
      # Risk metrics. expectancy = avg_pnl (rata-rata %/trade); metrik di bawah
      # nil kalau data belum cukup — view merender "—".
      expectancy:    avg_pnl,
      profit_factor: risk[:profit_factor],
      max_drawdown:  risk[:max_drawdown],
      sharpe:        risk[:sharpe]
    }
  end
end
