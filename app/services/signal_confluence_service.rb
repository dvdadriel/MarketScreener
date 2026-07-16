# Confluence-based signal generation.
#
# Pendekatan: untuk tiap simbol, kita evaluate banyak indikator di banyak timeframes.
# Signal hanya fire kalau:
#   1. Trend bias di higher TF jelas (bullish/bearish, bukan neutral)
#   2. Setidaknya MIN_CONFLUENCE indikator sejalan dengan trend
#   3. Sinyal di lower TF terkonfirmasi oleh higher TF (multi-TF agreement)
#
# Output: 1 signal per simbol (bukan 1 per strategy per TF — itu noisy)
class SignalConfluenceService
  CRYPTO_TIMEFRAMES = {
    trend:    %w[4h 1d],         # higher TF = trend context
    primary:  %w[1h 4h],         # main signal TF
    trigger:  %w[5m 15m]         # entry timing (scalping)
  }.freeze

  STOCK_TIMEFRAMES = {
    trend:    %w[1d],
    primary:  %w[1d 1h],
    trigger:  %w[1h]
  }.freeze

  # Minimum jumlah indikator yang harus align untuk fire signal (out of ~10)
  MIN_CONFLUENCE = 5      # was 3, tightened to reduce noise
  MIN_SCORE      = 0.75   # sweep sempat pilih 0.85 tapi itu ARTEFAK (data 1h historis bolong).
                          # Walk-forward dengan 1h lengkap: confluence ~break-even IS, RUGI OOS —
                          # tak ada edge tervalidasi. 0.85 tak lebih baik. Lihat list_improvement A.
  MIN_ATR_PCT    = 0.5    # was 0.3, require more volatility

  # as_of: batasi candle sampai timestamp ini (backtest, tanpa lookahead). nil = live.
  def initialize(symbol:, asset_type:, as_of: nil)
    @symbol = symbol
    @asset_type = asset_type
    @as_of      = as_of
    @tf_config  = asset_type == "stock" ? STOCK_TIMEFRAMES : CRYPTO_TIMEFRAMES
    @indicators = load_indicators
  end

  def evaluate
    return nil unless @indicators[:primary]&.any?

    trend = determine_trend
    return nil if trend == :neutral   # gatekeeper: jangan trade pasar choppy

    return nil unless tradeable_volatility?
    return nil unless tradeable_liquidity?

    checks = run_checks
    return nil if checks.empty?

    bullish = checks.count { |c| c[:direction] == :bullish }
    bearish = checks.count { |c| c[:direction] == :bearish }

    # Weighted scoring: volume-confirmed signals dapat bobot lebih
    bull_weight = checks.select { |c| c[:direction] == :bullish }.sum { |c| c[:weight] || 1.0 }
    bear_weight = checks.select { |c| c[:direction] == :bearish }.sum { |c| c[:weight] || 1.0 }
    total_weight = bull_weight + bear_weight

    dominant_count, dominant_dir, dom_weight = if bull_weight > bear_weight
      [ bullish, :bullish, bull_weight ]
    elsif bear_weight > bull_weight
      [ bearish, :bearish, bear_weight ]
    else
      [ 0, nil, 0 ]
    end

    return nil if dominant_count < min_confluence
    return nil if dominant_dir != trend

    score = (dom_weight.to_f / total_weight).round(4)
    return nil if score < min_score

    side = dominant_dir == :bullish ? "BUY" : "SELL"

    # BTC dominance gate (crypto only): block alt BUY kalau BTC lagi dump
    return nil if side == "BUY" && @asset_type == "crypto" && BtcMarketState.alt_buy_blocked?(@symbol)

    # IHSG regime gate (stock only): block BUY saham saat indeks risk-off
    return nil if side == "BUY" && @asset_type == "stock" && IdxMarketState.long_blocked?

    levels = compute_levels(side)

    {
      symbol:      @symbol,
      strategy:    "CONFLUENCE_#{dominant_dir.to_s.upcase}",
      signal_type: side,
      score:       score,
      asset_type:  @asset_type,
      fired_at:    Time.current,
      metadata: {
        trend:           trend,
        confluence:      "#{dominant_count}/#{checks.size}",
        bullish_count:   bullish,
        bearish_count:   bearish,
        checks:          checks.map { |c| { name: c[:name], dir: c[:direction], tf: c[:tf] } },
        atr_pct:         primary_indicator&.atr_pct&.round(2),
        timeframe:       "multi"
      }.merge(levels)
    }
  end

  # ATR-based stop loss & take profit (with percentage fallback).
  # SL = 1.5x ATR away, TP = 3x ATR away (R:R 1:2)
  def compute_levels(side)
    ind = primary_indicator
    return {} unless ind

    entry = ind.last_close
    return {} if entry.nil? || entry.zero?

    atr = ind.atr

    # Determine SL/TP distances: use ATR if available, else fallback to %
    sl_distance, tp_distance, source = if atr && atr.positive?
      [ atr * 1.5, atr * 3.0, "atr" ]
    else
      # Fallback: 3% SL, 6% TP (R:R 1:2)
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
      entry_price: entry.round(8),
      sl_price:    sl.round(8),
      tp_price:    tp.round(8),
      sl_pct:      sl_pct,
      tp_pct:      tp_pct,
      risk_reward: (tp_pct.abs / sl_pct.abs).round(2),
      level_source: source
    }
  end

  # Static helper — used by SignalEvaluatorJob to skip cooldown'd symbols
  def self.cooldown?(symbol)
    TradingSignal.where(symbol: symbol)
                 .where("strategy LIKE 'CONFLUENCE_%'")
                 .where("fired_at > ?", 4.hours.ago)
                 .exists?
  end

  private

  def load_indicators
    out = { trend: [], primary: [], trigger: [] }

    @tf_config.each do |role, timeframes|
      timeframes.each do |tf|
        scope = Candle.for_asset(@asset_type).for_symbol(@symbol).for_timeframe(tf)
        scope = scope.where("opened_at <= ?", @as_of) if @as_of
        candles = scope.ordered.last(220)
        next if candles.length < 30
        out[role] << { tf: tf, ind: IndicatorService.new(candles), candles: candles }
      end
    end
    out
  end

  def primary_indicator
    @indicators[:primary].first&.dig(:ind)
  end

  # === TREND FILTER ===
  # Bias dari TF tertinggi yang tersedia. Fallback ke primary TF kalau trend TF empty.
  def determine_trend
    trend_set = @indicators[:trend]
    trend_set = @indicators[:primary] if trend_set.empty?    # fallback
    return :neutral if trend_set.empty?

    biases = trend_set.map do |entry|
      ind = entry[:ind]
      ind.trend_bias != :neutral ? ind.trend_bias : ind.short_trend_bias
    end

    bullish = biases.count(:bullish)
    bearish = biases.count(:bearish)

    # Konflik = neutral; tanpa konflik, dominant direction
    if bullish > 0 && bearish > 0
      :neutral
    elsif bullish > 0
      :bullish
    elsif bearish > 0
      :bearish
    else
      :neutral
    end
  end

  # Ambang bisa di-override (thread-local) untuk sweep backtest; default = konstanta produksi.
  def min_confluence = Thread.current[:bt_min_confluence] || MIN_CONFLUENCE
  def min_score      = Thread.current[:bt_min_score] || MIN_SCORE

  def tradeable_volatility?
    return true unless primary_indicator
    atr = primary_indicator.atr_pct
    atr.nil? || atr >= MIN_ATR_PCT
  end

  # Filter likuiditas (saham saja): edge confluence cuma bertahan di saham likuid
  # (bukti backtest). Turnover = avg volume 20 hari × close, ambang sama dgn scanner.
  def tradeable_liquidity?
    return true unless @asset_type == "stock"
    ind = primary_indicator
    return false unless ind
    avg_vol = ind.average_volume(period: 20)
    close   = ind.last_close
    return false if avg_vol.nil? || close.nil?
    (avg_vol * close) >= IdxScannerService::MIN_LIQUIDITY
  end

  # === CONFLUENCE CHECKS ===
  # Tiap check return { name, direction (:bullish/:bearish/nil), tf, weight }
  def run_checks
    checks = []

    (@indicators[:primary] + @indicators[:trigger]).each do |entry|
      tf = entry[:tf]
      ind = entry[:ind]
      candles = entry[:candles]
      regime = market_regime(ind)

      # Regime-aware: di market ranging, MACD jadi tidak reliable; di market trending, RSI extreme jadi false signal
      checks << check_rsi(ind, tf, regime)
      checks << check_macd(ind, tf, regime)
      checks << check_bb(ind, candles, tf)
      checks << check_volume(ind, candles, tf)
      checks << check_ma_position(ind, tf)
    end

    checks.compact.reject { |c| c[:direction].nil? }
  end

  # Market regime: :trending / :ranging / :transitioning
  def market_regime(ind)
    adx_data = ind.adx
    return :transitioning unless adx_data
    case adx_data[:adx]
    when 0..20 then :ranging
    when 20..25 then :transitioning
    else :trending
    end
  end

  # RSI mean-reversion works best in ranging market.
  # Di market trending kuat, RSI extreme jadi false signal (trend continuation).
  def check_rsi(ind, tf, regime = nil)
    rsi = ind.rsi
    return nil unless rsi
    return nil if regime == :trending   # skip RSI extreme di market trending

    dir = if rsi < 30 then :bullish
    elsif rsi > 70 then :bearish
    end
    { name: "rsi(#{rsi.round(1)})", direction: dir, tf: tf, weight: 1.0 }
  end

  # MACD trend-follow works in trending market.
  # Di ranging, MACD jadi whipsaw (kiri-kanan, tidak reliable).
  def check_macd(ind, tf, regime = nil)
    m = ind.macd
    return nil unless m && m[:prev_histogram]
    return nil if regime == :ranging   # skip MACD di ranging market

    dir = if m[:histogram] > 0 && m[:histogram] > m[:prev_histogram] then :bullish
    elsif m[:histogram] < 0 && m[:histogram] < m[:prev_histogram] then :bearish
    end
    # Bobot lebih tinggi saat trending kuat
    weight = regime == :trending ? 1.5 : 1.0
    { name: "macd", direction: dir, tf: tf, weight: weight }
  end

  def check_bb(ind, candles, tf)
    bb = ind.bollinger
    return nil unless bb
    close = candles.last.close.to_f
    dir = if close < bb[:lower] then :bullish
    elsif close > bb[:upper] then :bearish
    end
    { name: "bb", direction: dir, tf: tf, weight: 1.0 }
  end

  # Volume confirms intent — bobot lebih tinggi karena conviction tinggi
  def check_volume(ind, candles, tf)
    avg = ind.average_volume(period: 20)
    return nil if avg.nil? || avg.zero?

    last = candles.last
    prev = candles[-2]
    return nil unless prev

    ratio = last.volume.to_f / avg
    return nil if ratio < 2.5

    price_change = (last.close.to_f - prev.close.to_f) / prev.close.to_f
    dir = price_change > 0 ? :bullish : :bearish
    # Bobot scale dengan ratio (volume tinggi = signal lebih kuat)
    weight = (1.0 + (ratio - 2.5) / 5.0).clamp(1.0, 2.0).round(2)
    { name: "vol(#{ratio.round(1)}x)", direction: dir, tf: tf, weight: weight }
  end

  def check_ma_position(ind, tf)
    return nil unless ind.short_trend_bias != :neutral
    { name: "ma50", direction: ind.short_trend_bias, tf: tf, weight: 1.0 }
  end
end
