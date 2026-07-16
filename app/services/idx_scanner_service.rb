class IdxScannerService
  # Swing setup ideal:
  #  - RSI 35-50 (oversold tapi belum extreme, ada room untuk naik)
  #  - MACD histogram positif & rising (momentum baru kembali)
  #  - Close > MA50 (trend bullish jangka menengah)
  #  - Volume terakhir > avg 20 hari × 1.2 (ada akumulasi)
  #  - Bollinger position: dekat middle band (bukan overbought di upper)
  MIN_CANDLES = 60
  MIN_LIQUIDITY = 1_000_000_000  # Rp 1 miliar avg daily turnover (strict liquidity)
  MIN_ATR_PCT = 1.5              # buang saham likuid tapi flat/mati (jangan saham tak bergerak)
  RS_LOOKBACK = 60               # ~3 bulan bursa untuk relative strength vs IHSG

  # as_of/symbols: dukung backtest (batasi candle & universe). nil = live/full.
  def initialize(as_of: nil, symbols: nil)
    @as_of   = as_of
    @symbols = symbols
  end

  def universe
    @symbols || IdxUniverseService.all
  end

  def call
    # Gate regime IHSG: jangan buka long baru saat indeks risk-off.
    if IdxMarketState.long_blocked?
      Rails.logger.info("[IdxScannerService] skip — #{IdxMarketState.reason}")
      return []
    end

    index_return = compute_index_return
    candidates = []

    universe.each do |symbol|
      scope = Candle.for_asset("stock").for_symbol(symbol).for_timeframe("1d")
      scope = scope.where("opened_at <= ?", @as_of) if @as_of
      candles = scope.ordered.last(120)
      next if candles.length < MIN_CANDLES

      result = analyze(symbol, candles, index_return)
      next unless result

      candidates << result
    end

    candidates
      .reject { |c| c[:composite_score] < 70 }    # was 50, now only strong picks
      .sort_by { |c| -c[:composite_score] }
  end

  # Return IHSG selama RS_LOOKBACK bar, atau nil kalau data indeks tak ada.
  def compute_index_return
    closes = IdxMarketState.ihsg_closes
    return nil if closes.length <= RS_LOOKBACK
    (closes.last / closes[-RS_LOOKBACK - 1]) - 1.0
  end

  private

  def analyze(symbol, candles, index_return = nil)
    ind = IndicatorService.new(candles)

    rsi        = ind.rsi(period: 14)
    macd       = ind.macd
    ma50       = ind.sma(period: 50)
    avg_vol_20 = ind.average_volume(period: 20)
    last_close = ind.last_close
    last_vol   = ind.last_volume

    return nil if [ rsi, macd, ma50, avg_vol_20, last_close, last_vol ].any?(&:nil?)
    return nil if avg_vol_20.zero? || ma50.zero?

    # Gate keras tren: jangan tangkap pisau jatuh — di bawah MA50 = downtrend.
    return nil if last_close < ma50

    # Gate movement: buang saham likuid tapi flat (jangan saham tak bergerak).
    atr_pct = ind.atr_pct
    return nil if atr_pct.nil? || atr_pct < MIN_ATR_PCT

    # Liquidity filter (avg turnover = avg_vol × last_close)
    avg_turnover = avg_vol_20 * last_close
    return nil if avg_turnover < MIN_LIQUIDITY

    rs = relative_strength(candles, index_return)

    scores = {
      rsi:    score_rsi(rsi),
      macd:   score_macd(macd),
      trend:  score_trend(last_close, ma50),
      volume: score_volume(last_vol, avg_vol_20),
      rs:     score_rs(rs)
    }

    # ponytail: composite = rata-rata 5 skor equal-weight. Ambang 70 mungkin perlu
    # retune setelah komponen RS ditambah — validasi lewat backtesting engine (list_improvement #3).
    composite = (scores.values.sum / scores.size).round

    {
      symbol:          symbol,
      composite_score: composite,
      rsi:             rsi.round(2),
      macd_hist:       macd[:histogram],
      macd_rising:    !macd[:prev_histogram].nil? && macd[:histogram] > macd[:prev_histogram],
      last_close:      last_close,
      ma50:            ma50.round(2),
      price_vs_ma50:   ((last_close - ma50) / ma50 * 100).round(2),
      volume_ratio:    (last_vol / avg_vol_20).round(2),
      atr_pct:         atr_pct,
      relative_strength: rs&.round(4),
      avg_turnover:    avg_turnover.round,
      breakdown:       scores
    }
  end

  # Relative strength = return saham - return IHSG selama RS_LOOKBACK bar.
  # nil kalau data indeks/saham kurang → score_rs kasih nilai netral.
  def relative_strength(candles, index_return)
    return nil if index_return.nil? || candles.length <= RS_LOOKBACK
    closes = candles.map { |c| c.close.to_f }
    past = closes[-RS_LOOKBACK - 1]
    return nil if past.nil? || past.zero?
    stock_return = (closes.last / past) - 1.0
    stock_return - index_return
  end

  # RS positif (outperform IHSG) = leader; negatif = laggard.
  def score_rs(rs)
    return 50 if rs.nil?   # netral saat data indeks tak tersedia
    pct = rs * 100
    case pct
    when 10..Float::INFINITY then 100
    when 5...10  then 85
    when 0...5   then 70
    when -5...0  then 45
    when -10...-5 then 25
    else 10
    end
  end

  # RSI sweet spot for swing entry: 35-50 (oversold bounce candidate)
  def score_rsi(rsi)
    case rsi
    when 35..45 then 100
    when 45..50 then 85
    when 30..35 then 75
    when 50..55 then 60
    when 25..30 then 50
    when 55..65 then 35
    when 65..70 then 15
    else 0
    end
  end

  # MACD: positive AND rising = best; positive only = ok; negative = bad
  def score_macd(macd)
    h = macd[:histogram]
    prev = macd[:prev_histogram]

    return 50 if prev.nil?

    if h > 0 && h > prev
      100
    elsif h > 0
      70
    elsif h < 0 && h > prev   # negative but improving = early reversal
      55
    elsif h < 0 && h < prev
      10
    else
      30
    end
  end

  # Price vs MA50: just above = ideal swing entry; way above = overextended
  def score_trend(close, ma50)
    pct = (close - ma50) / ma50 * 100

    case pct
    when 0..3   then 100      # just crossed above
    when 3..7   then 85
    when -2..0  then 75       # right at MA, possible bounce
    when 7..12  then 60
    when -5..-2 then 50       # mild dip below
    when 12..20 then 30       # overextended
    else 10
    end
  end

  # Volume: 1.2x-3x avg = healthy interest; over 5x = unusual (possibly news)
  def score_volume(vol, avg)
    ratio = vol / avg

    case ratio
    when 1.2..2.5 then 100
    when 2.5..4.0 then 85
    when 1.0..1.2 then 70
    when 4.0..7.0 then 60
    when 0.8..1.0 then 50
    when 7.0..15  then 30
    else 15
    end
  end
end
