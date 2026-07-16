# Metrik risiko dari deret pnl_pct per trade (urut waktu exit).
# Dipakai bareng PaperTradeStats (paper trading live) & BacktestService (histori)
# supaya definisinya identik di kedua tempat.
module RiskMetrics
  module_function

  # pnls: Array<Float> pnl_pct per closed trade, urut waktu exit.
  #  - profit_factor = Σgain / |Σloss| (>1 = +EV). nil kalau belum ada loss.
  #  - max_drawdown  = penurunan terbesar equity curve kumulatif (poin %).
  #  - sharpe        = mean/stdev per-trade (BUKAN annualized — tak ada asumsi frekuensi).
  def compute(pnls)
    return { profit_factor: nil, max_drawdown: nil, sharpe: nil } if pnls.empty?

    gain = pnls.select(&:positive?).sum
    loss = pnls.select(&:negative?).sum.abs
    profit_factor = loss.zero? ? nil : (gain / loss).round(2)

    peak = 0.0
    cum = 0.0
    maxdd = 0.0
    pnls.each do |p|
      cum += p
      peak = cum if cum > peak
      dd = peak - cum
      maxdd = dd if dd > maxdd
    end

    n = pnls.size
    mean = pnls.sum / n
    var = pnls.sum { |p| (p - mean)**2 } / n
    std = Math.sqrt(var)
    sharpe = std.zero? ? nil : (mean / std).round(2)

    { profit_factor: profit_factor, max_drawdown: maxdd.round(2), sharpe: sharpe }
  end
end
