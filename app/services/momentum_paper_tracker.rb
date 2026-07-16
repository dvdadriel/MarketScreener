# Replay momentum_snapshots → equity paper portfolio (forward tracking).
# Aturan SAMA dengan MomentumBacktestService (rebalance tiap 21 hari-snapshot,
# equal-weight, fee 0.4%/leg atas porsi yang berubah) supaya angka forward bisa
# dibandingkan apple-to-apple dengan backtest. Equity dihitung on-the-fly dari
# snapshot + candle — tanpa state tersimpan, tak bisa drift.
class MomentumPaperTracker
  REBALANCE_DAYS = MomentumBacktestService::REBALANCE_DAYS   # 21
  COST_PCT       = 0.4
  TOP_N          = MomentumRankingService::TOP_N

  def call
    dates = MomentumSnapshot.snapshot_dates
    return empty_report if dates.empty?

    equity = 100.0
    peak = 100.0
    maxdd = 0.0
    holdings = []
    prev_px  = {}
    daily_rets = []
    curve = []   # [[date, equity], ...] untuk slice mingguan di laporan

    dates.each_with_index do |d, i|
      # 1) mark-to-market holding harian
      unless holdings.empty?
        rets = holdings.map { |s| px = price_at(s, d); pv = prev_px[s]; (px && pv && pv > 0) ? px / pv - 1.0 : 0.0 }
        r = rets.sum / rets.size
        equity *= (1 + r)
        daily_rets << r
      end
      holdings.each { |s| px = price_at(s, d); prev_px[s] = px if px }

      # 2) rebalance tiap REBALANCE_DAYS hari-snapshot (hari pertama = rebalance)
      if (i % REBALANCE_DAYS).zero?
        rows   = MomentumSnapshot.for_date(d).picks.order(:rank)
        target = rows.pluck(:symbol)
        changed = (holdings - target).size + (target - holdings).size
        equity *= (1 - (COST_PCT / 100.0) * changed / TOP_N) if changed.positive?

        holdings = target
        rows.each { |row| prev_px[row.symbol] = row.price.to_f }
      end

      # 3) drawdown akun (harian)
      peak  = equity if equity > peak
      dd    = (peak - equity) / peak * 100
      maxdd = dd if dd > maxdd
      curve << [ d, equity.round(4) ]
    end

    last = MomentumSnapshot.for_date(dates.last)
    {
      inception:      dates.first,
      as_of:          dates.last,
      tracked_days:   dates.size,
      equity:         equity.round(2),
      total_return:   (equity - 100).round(2),
      max_drawdown:   maxdd.round(2),
      ihsg_return:    ihsg_return(dates.first, dates.last),
      regime_today:   last.first&.regime,
      holdings:       holdings,
      equity_curve:   curve
    }
  end

  private

  def empty_report
    { inception: nil, as_of: nil, tracked_days: 0, equity: 100.0, total_return: 0.0,
      max_drawdown: 0.0, ihsg_return: nil, regime_today: nil, holdings: [], equity_curve: [] }
  end

  # Close terakhir pada/atau sebelum tanggal d (cache per simbol).
  def price_at(symbol, d)
    @candles ||= {}
    @candles[symbol] ||= Candle.for_asset("stock").for_symbol(symbol).for_timeframe("1d")
                               .ordered.pluck(:opened_at, :close)
    row = @candles[symbol].reverse_each.find { |t, _| t.to_date <= d }
    row&.last&.to_f
  end

  # Benchmark: beli-tahan IHSG di rentang tracking (butuh histori ^JKSE tersimpan).
  def ihsg_return(from, to)
    rows = Candle.where(asset_type: "index", symbol: IdxMarketState::SYMBOL, timeframe: "1d")
                 .order(:opened_at).pluck(:opened_at, :close)
    first = rows.find { |t, _| t.to_date >= from }&.last&.to_f
    last  = rows.reverse_each.find { |t, _| t.to_date <= to }&.last&.to_f
    return nil if first.nil? || last.nil? || first.zero?
    ((last / first - 1.0) * 100).round(2)
  end
end
