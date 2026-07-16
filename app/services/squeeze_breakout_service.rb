# Setup mandiri: volatility squeeze LALU breakout range + konfirmasi volume.
#
# STATUS (2026-07-15): DINONAKTIFKAN UNTUK SAHAM di SignalEvaluatorJob — backtest
# 365d+fee membuktikan net-rugi di semua potongan (LQ45 & universe penuh: PF < 1,
# expectancy & Sharpe negatif). Kode dipertahankan untuk jalur CRYPTO (belum diuji
# di sana; crypto sendiri sedang off via CRYPTO_ENABLED). Kalau crypto diaktifkan
# lagi: backtest dulu sebelum percaya. Detail: guideline/docs/ + list_improvement.
class SqueezeBreakoutService
  STRATEGY   = "SQUEEZE_BREAKOUT"
  PRIMARY_TF = { "stock" => "1d", "crypto" => "1h" }.freeze

  SQUEEZE_PERCENTILE = 15.0   # squeeze kalau lebar band <= persentil ini
  SQUEEZE_WINDOW     = 3      # cek 3 bar terakhir (band sempat tight lalu melebar ke breakout)
  BREAKOUT_LOOKBACK  = 20     # range N bar untuk breakout
  VOLUME_MULT        = 1.5    # volume bar terakhir > 1.5x avg(20)
  COOLDOWN           = 4.hours

  def self.cooldown?(symbol)
    TradingSignal.where(symbol: symbol, strategy: STRATEGY)
                 .where("fired_at > ?", COOLDOWN.ago)
                 .exists?
  end

  # as_of: batasi candle sampai timestamp ini (backtest, tanpa lookahead). nil = live.
  def initialize(symbol:, asset_type:, as_of: nil)
    @symbol     = symbol
    @asset_type = asset_type
    @tf         = PRIMARY_TF[asset_type] || "1h"
    scope       = Candle.for_asset(asset_type).for_symbol(symbol).for_timeframe(@tf)
    scope       = scope.where("opened_at <= ?", as_of) if as_of
    candles     = scope.ordered.last(220)
    @ind        = IndicatorService.new(candles) if candles.length >= 30
  end

  def evaluate
    return nil unless @ind

    pctl = squeeze_percentile
    return nil if pctl.nil? || pctl > SQUEEZE_PERCENTILE

    breakout = @ind.range_breakout(lookback: BREAKOUT_LOOKBACK)
    return nil unless breakout

    vol_ratio = volume_ratio
    return nil if vol_ratio.nil? || vol_ratio < VOLUME_MULT

    side   = breakout[:direction] == :bullish ? "BUY" : "SELL"

    # IHSG regime gate (stock only): block BUY saham saat indeks risk-off
    return nil if side == "BUY" && @asset_type == "stock" && IdxMarketState.long_blocked?

    levels = compute_levels(side)
    return nil if levels.empty?

    {
      symbol:      @symbol,
      strategy:    STRATEGY,
      signal_type: side,
      score:       score(pctl, vol_ratio),
      asset_type:  @asset_type,
      fired_at:    Time.current,
      metadata: {
        bb_width_pctl:  pctl.round(2),
        breakout_level: breakout[:level],
        vol_ratio:      vol_ratio.round(2),
        timeframe:      @tf
      }.merge(levels)
    }
  end

  private

  # Squeeze kalau band tight (persentil rendah) di salah satu SQUEEZE_WINDOW bar terakhir.
  def squeeze_percentile
    (0...SQUEEZE_WINDOW).map { |off| @ind.bb_width_percentile(offset: off) }.compact.min
  end

  def volume_ratio
    avg = @ind.average_volume(period: 20)
    return nil if avg.nil? || avg.zero?
    @ind.last_volume / avg
  end

  def score(pctl, vol_ratio)
    tight_bonus = ((SQUEEZE_PERCENTILE - pctl) / SQUEEZE_PERCENTILE * 0.15).clamp(0.0, 0.15)
    vol_bonus   = ((vol_ratio - VOLUME_MULT) / 5.0).clamp(0.0, 0.10)
    (0.7 + tight_bonus + vol_bonus).clamp(0.0, 0.95).round(4)
  end

  # ATR-based SL/TP (1.5x / 3x, R:R 1:2), bentuk sama dengan SignalConfluenceService.
  def compute_levels(side)
    entry = @ind.last_close
    return {} if entry.nil? || entry.zero?

    atr = @ind.atr
    sl_distance, tp_distance, source = if atr && atr.positive?
      [ atr * 1.5, atr * 3.0, "atr" ]
    else
      [ entry * 0.03, entry * 0.06, "pct" ]
    end

    if side == "BUY"
      sl = entry - sl_distance
      tp = entry + tp_distance
    else
      sl = entry + sl_distance
      tp = entry - tp_distance
    end

    sl_pct = ((sl - entry) / entry * 100).round(2)
    tp_pct = ((tp - entry) / entry * 100).round(2)

    {
      entry_price:  entry.round(8),
      sl_price:     sl.round(8),
      tp_price:     tp.round(8),
      sl_pct:       sl_pct,
      tp_pct:       tp_pct,
      risk_reward:  (tp_pct.abs / sl_pct.abs).round(2),
      level_source: source
    }
  end
end
