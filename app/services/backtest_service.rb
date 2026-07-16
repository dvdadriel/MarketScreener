# Backtesting engine (MVP — validasi strategi apa adanya).
#
# Menjalankan service sinyal YANG SAMA dengan produksi di candle historis (via
# param `as_of:`), lalu simulasi entry/exit realistis. Prinsip anti-bohong:
#   - Satu sumber logika (reuse SignalConfluenceService/SqueezeBreakoutService).
#   - Tanpa lookahead: sinyal fire dari bar <= T; entry di OPEN bar T+1.
#   - Exit konservatif: SL dicek sebelum TP dalam satu bar.
#
# Batasan MVP (disengaja, bukan lubang): gate regime IHSG di-bypass (lihat
# IdxMarketState.long_blocked?); tanpa position sizing/compounding; tanpa biaya
# transaksi/slippage. Semua = fase lanjut. Lihat guideline/list_improvement.md.
class BacktestService
  STRATEGIES = {
    "confluence" => SignalConfluenceService,
    "squeeze"    => SqueezeBreakoutService
  }.freeze

  MIN_HISTORY = 60   # bar minimum sebelum boleh mulai backtest satu simbol
  SWING_TOP_N = 10   # jumlah pick harian SWING_PICK (sama dgn IdxScannerJob)

  Trade = Struct.new(
    :symbol, :strategy, :side, :entry_at, :entry, :exit_at, :exit,
    :pnl_pct, :sl_pct, :exit_reason, :exit_index,
    keyword_init: true
  )

  # cost_pct:     biaya round-trip (beli+jual, %) dipotong dari tiap trade. IDX ~0.3-0.5%.
  # slippage_pct: pergerakan harga merugikan per-leg (entry & exit). Gap menembus stop
  #               diisi di harga open bar (bukan di level SL/TP) — realistis untuk daily IDX.
  # Default 0.0 = kompatibel dengan pemanggilan langsung/test; rake pakai default realistis.
  # risk_pct: risiko per-trade (% ekuitas). >0 aktifkan position sizing → equity curve
  #           ber-compound & max drawdown akun NYATA. 0 = matikan (metrik per-trade saja).
  MAX_POSITION = 1.0   # tanpa leverage: maksimum 100% ekuitas per posisi

  # offset_days: geser window mundur N hari (untuk uji out-of-sample periode lampau).
  #              offset 0 = window terakhir; offset 365 = setahun sebelumnya.
  # regime_gate: false (default) = gate IHSG di-bypass (ukur edge mentah).
  #              true = terapkan gate regime AS-OF histori (validasi dampak gate).
  def initialize(symbols:, asset_type: "stock", days: 365, strategies: STRATEGIES.keys, cost_pct: 0.0, slippage_pct: 0.0, risk_pct: 0.0, offset_days: 0, regime_gate: false)
    @symbols      = Array(symbols)
    @asset_type   = asset_type
    @days         = days.to_i
    @strategies   = strategies & (STRATEGIES.keys + [ "swing_pick" ])
    @cost_pct     = cost_pct.to_f
    @slippage_pct = slippage_pct.to_f
    @risk_pct     = risk_pct.to_f
    @offset_days  = offset_days.to_i
    @regime_gate  = regime_gate
  end

  def call
    swing = @strategies.include?("swing_pick")
    if @regime_gate || swing
      ensure_index_history          # ^JKSE untuk regime as-of + relative strength
    else
      Thread.current[:backtest_bypass_regime] = true
    end

    per_symbol = @strategies & STRATEGIES.keys
    trades = []
    bars_by_symbol = {}
    @symbols.each do |sym|
      ensure_history(sym)
      bars = daily_bars(sym)
      bars_by_symbol[sym] = bars
      next if bars.length < MIN_HISTORY
      per_symbol.each { |strat| trades.concat(run_strategy(sym, strat, bars)) }
    rescue => e
      Rails.logger.error("[BacktestService] #{sym}: #{e.class}: #{e.message}")
    end

    trades.concat(run_swing_pick(bars_by_symbol)) if swing
    build_report(trades)
  ensure
    Thread.current[:backtest_bypass_regime] = false
    Thread.current[:backtest_as_of] = nil
  end

  # SWING_PICK cross-sectional: tiap hari scan universe as-of, ambil top-N pick,
  # entry hari berikutnya, exit pakai aturan daily PaperTrade::RULES (SL -8/TP +15).
  # Regime + RS dihitung as-of (Thread as_of) — gate bagian dari strateginya.
  def run_swing_pick(bars_by_symbol)
    ref = bars_by_symbol.values.max_by(&:length) || []
    return [] if ref.empty?

    end_at = ref.last.opened_at - @offset_days.days
    cutoff = end_at - @days.days
    dates  = ref.map(&:opened_at).select { |d| d >= cutoff && d <= end_at }

    rules   = PaperTrade::RULES[:daily]
    holding = {}   # symbol => exit_at (jangan re-entry selama masih hold)
    trades  = []

    dates.each do |t|
      Thread.current[:backtest_as_of] = t
      picks = IdxScannerService.new(as_of: t, symbols: @symbols).call.first(SWING_TOP_N)
      picks.each do |p|
        sym = p[:symbol]
        next if holding[sym] && t <= holding[sym]
        bars = bars_by_symbol[sym]
        entry_index = bars.index { |b| b.opened_at > t }
        next unless entry_index

        sig = { symbol: sym, strategy: "SWING_PICK", signal_type: "BUY",
                metadata: { timeframe: "1d", sl_pct: rules[:sl_pct].to_f, tp_pct: rules[:tp_pct].to_f } }
        trade = simulate(sig, bars, entry_index)
        if trade
          trades << trade
          holding[sym] = trade.exit_at
        end
      end
    end
    trades
  end

  private

  # === Walk satu strategi di satu simbol ===
  def run_strategy(symbol, strat, bars)
    klass  = STRATEGIES[strat]
    end_at = bars.last.opened_at - @offset_days.days
    cutoff = end_at - @days.days
    trades = []

    i = start_index(bars, cutoff)
    while i < bars.length - 1
      t = bars[i].opened_at
      break if t > end_at   # batas atas window (out-of-sample)
      Thread.current[:backtest_as_of] = t if @regime_gate   # regime dihitung as-of bar ini
      sig = klass.new(symbol: symbol, asset_type: @asset_type, as_of: t).evaluate
      if sig && %w[BUY SELL].include?(sig[:signal_type])
        trade = simulate(sig, bars, i + 1)
        if trade
          trades << trade
          i = trade.exit_index + 1   # satu posisi per (simbol,strategi) pada satu waktu
          next
        end
      end
      i += 1
    end
    trades
  end

  # Bar entry pertama: dalam window lookback DAN punya cukup histori sebelumnya.
  def start_index(bars, cutoff)
    idx = bars.index { |b| b.opened_at >= cutoff } || bars.length
    [ idx, MIN_HISTORY ].max
  end

  # === Simulasi satu trade dari sinyal ===
  # Entry di OPEN bar entry_index. SL/TP pakai persentase dari sinyal (ATR-based),
  # diterapkan ke harga entry aktual. max_hours -> jumlah bar harian.
  def simulate(sig, bars, entry_index)
    return nil if entry_index >= bars.length

    side      = sig[:signal_type]
    raw_entry = bars[entry_index].open.to_f
    return nil if raw_entry.zero?

    # sl_pct/tp_pct ada DI DALAM metadata (evaluate merge levels ke metadata).
    meta   = sig[:metadata] || {}
    sl_pct = meta[:sl_pct]
    tp_pct = meta[:tp_pct]
    return nil if sl_pct.nil? || tp_pct.nil?

    entry = slip(raw_entry, side, :entry)   # entry adverse (beli lebih tinggi / jual lebih rendah)
    sl = entry * (1 + sl_pct.to_f / 100.0)
    tp = entry * (1 + tp_pct.to_f / 100.0)
    max_bars = [ (max_hours_for(sig) / 24.0).ceil, 1 ].max
    last = [ entry_index + max_bars, bars.length - 1 ].min

    (entry_index..last).each do |j|
      bar  = bars[j]
      hi   = bar.high.to_f
      lo   = bar.low.to_f
      open = bar.open.to_f

      # SL dicek sebelum TP (konservatif). Fill gap-aware: kalau bar OPEN sudah
      # melewati level, isi di open (bukan di level) — lebih pesimis & realistis.
      if side == "BUY"
        return exit_at(sig, side, entry, [ open, sl ].min, bar, j, "SL") if lo <= sl
        return exit_at(sig, side, entry, [ open, tp ].max, bar, j, "TP") if hi >= tp
      else
        return exit_at(sig, side, entry, [ open, sl ].max, bar, j, "SL") if hi >= sl
        return exit_at(sig, side, entry, [ open, tp ].min, bar, j, "TP") if lo <= tp
      end
    end

    # Tak kena SL/TP dalam batas waktu -> tutup di close bar terakhir.
    exit_at(sig, side, entry, bars[last].close.to_f, bars[last], last, "TIME")
  end

  # Fill exit dengan slippage adverse lalu hitung pnl.
  def exit_at(sig, side, entry, level, bar, index, reason)
    close(sig, side, entry, slip(level, side, :exit), bar, index, reason)
  end

  # Slippage adverse: entry BUY naik / SELL turun; exit BUY(jual) turun / SELL(beli) naik.
  def slip(price, side, leg)
    s = @slippage_pct / 100.0
    factor = if leg == :entry
      side == "BUY" ? (1 + s) : (1 - s)
    else
      side == "BUY" ? (1 - s) : (1 + s)
    end
    price * factor
  end

  def close(sig, side, entry, exit_price, bar, index, reason)
    pnl = side == "BUY" ? (exit_price - entry) / entry : (entry - exit_price) / entry
    pnl_pct = (pnl * 100) - @cost_pct   # potong biaya transaksi round-trip
    Trade.new(
      symbol: sig[:symbol], strategy: sig[:strategy], side: side,
      entry_at: nil, entry: entry.round(4),
      exit_at: bar.opened_at, exit: exit_price.round(4),
      pnl_pct: pnl_pct.round(4), sl_pct: sig.dig(:metadata, :sl_pct).to_f,
      exit_reason: reason, exit_index: index
    )
  end

  # max_hours dari PaperTrade::RULES (sumber tunggal aturan auto-close).
  def max_hours_for(sig)
    return PaperTrade::RULES[:daily][:max_hours] if sig[:strategy] == "SWING_PICK"
    tf = sig.dig(:metadata, :timeframe).to_s
    rules = PaperTrade::SCALP_TIMEFRAMES.include?(tf) ? PaperTrade::RULES[:scalp] : PaperTrade::RULES[:swing]
    rules[:max_hours]
  end

  # === Data ===
  def daily_bars(symbol)
    Candle.for_asset(@asset_type).for_symbol(symbol).for_timeframe("1d").ordered.to_a
  end

  # Pastikan histori cukup untuk window backtest; fetch Yahoo kalau cakupan kurang.
  # 1d (trend) bisa dalam (5y); 1h (confluence primary/trigger) dibatasi Yahoo ~730 hari.
  def ensure_history(symbol)
    ensure_tf(symbol, "1d", yahoo_range(cap_years: 5))
    # Confluence butuh candle 1h historis. Squeeze/scanner cuma 1d.
    ensure_tf(symbol, "1h", yahoo_range(cap_years: 2)) if @strategies.include?("confluence")
  end

  # Histori ^JKSE (asset_type "index") untuk regime gate as-of. Fetch sekali.
  def ensure_index_history
    sym = IdxMarketState::SYMBOL
    need_from = Time.current - (@days + @offset_days + 90).days
    earliest  = Candle.where(asset_type: "index", symbol: sym, timeframe: "1d").minimum(:opened_at)
    return if earliest && earliest <= need_from

    rows = YahooFinanceClient.new.klines(symbol: sym, interval: "1d", limit: 5000, range: yahoo_range(cap_years: 5))
    return if rows.blank?

    records = rows.map do |k|
      {
        symbol: sym, timeframe: "1d", asset_type: "index",
        open: k[:open], high: k[:high], low: k[:low], close: k[:close], volume: k[:volume],
        opened_at: k[:opened_at], created_at: Time.current, updated_at: Time.current
      }
    end
    Candle.upsert_all(records, unique_by: [ :symbol, :timeframe, :opened_at ],
                               update_only: [ :open, :high, :low, :close, :volume, :asset_type ])
  rescue => e
    Rails.logger.warn("[BacktestService] fetch index #{IdxMarketState::SYMBOL}: #{e.message}")
  end

  # Fetch timeframe `tf` kalau candle tersimpan belum mundur cukup jauh.
  def ensure_tf(symbol, tf, range)
    need_from = Time.current - (@days + @offset_days + 90).days
    earliest  = Candle.for_asset(@asset_type).for_symbol(symbol).for_timeframe(tf).minimum(:opened_at)
    return if earliest && earliest <= need_from

    rows = YahooFinanceClient.new.klines(symbol: symbol, interval: tf, limit: 5000, range: range)
    return if rows.blank?

    records = rows.map do |k|
      {
        symbol: symbol, timeframe: tf, asset_type: @asset_type,
        open: k[:open], high: k[:high], low: k[:low], close: k[:close], volume: k[:volume],
        opened_at: k[:opened_at], created_at: Time.current, updated_at: Time.current
      }
    end
    Candle.upsert_all(records, unique_by: [ :symbol, :timeframe, :opened_at ],
                               update_only: [ :open, :high, :low, :close, :volume, :asset_type ])
    sleep 0.3   # throttle Yahoo
  rescue => e
    Rails.logger.warn("[BacktestService] fetch #{symbol} #{tf}: #{e.message}")
  end

  # Rentang Yahoo cukup untuk window + offset + buffer, di-cap per timeframe.
  def yahoo_range(cap_years:)
    total_years = (@days + @offset_days + 200) / 365.0
    picked = [ 1, 2, 5 ].find { |y| total_years <= y } || 10
    "#{[ picked, cap_years ].min}y"
  end

  # === Laporan ===
  def build_report(trades)
    by_strat = trades.group_by(&:strategy_group)
    per_strategy = by_strat.map do |group, ts|
      sorted = ts.sort_by(&:exit_at)
      pnls   = sorted.map(&:pnl_pct)
      wins   = pnls.count(&:positive?)
      risk   = RiskMetrics.compute(pnls)
      sized  = sized_metrics(sorted)
      {
        strategy:      group,
        trades:        ts.size,
        win_rate:      pnls.empty? ? 0.0 : (wins.to_f / pnls.size * 100).round(1),
        expectancy:    pnls.empty? ? 0.0 : (pnls.sum / pnls.size).round(2),
        profit_factor: risk[:profit_factor],
        max_drawdown:  risk[:max_drawdown],
        sharpe:        risk[:sharpe],
        total_return:  sized&.dig(:total_return),
        max_dd_real:   sized&.dig(:max_drawdown_real)
      }
    end.sort_by { |s| -(s[:expectancy] || 0) }

    { days: @days, symbols: @symbols.size, total_trades: trades.size, risk_pct: @risk_pct, per_strategy: per_strategy }
  end

  # Position sizing risk-per-trade: tiap trade risiko @risk_pct ekuitas (posisi =
  # risk / |sl_pct|, tanpa leverage). Equity ber-compound → drawdown akun NYATA
  # (% dari puncak ekuitas, bukan penjumlahan poin-persen). trades: urut exit_at.
  def sized_metrics(trades)
    return nil if @risk_pct <= 0 || trades.empty?

    equity = 100.0
    peak   = 100.0
    maxdd  = 0.0
    trades.each do |t|
      sl = t.sl_pct.to_f.abs
      next if sl.zero?
      fraction = [ @risk_pct / sl, MAX_POSITION ].min
      equity  *= 1 + (fraction * t.pnl_pct / 100.0)
      peak     = equity if equity > peak
      dd       = (peak - equity) / peak * 100
      maxdd    = dd if dd > maxdd
    end

    { total_return: (equity - 100).round(2), max_drawdown_real: maxdd.round(2) }
  end
end

# Grup strategi untuk agregasi (CONFLUENCE_BULLISH & CONFLUENCE_BEARISH digabung).
class BacktestService::Trade
  def strategy_group
    strategy.to_s.start_with?("CONFLUENCE") ? "CONFLUENCE" : strategy.to_s
  end
end
