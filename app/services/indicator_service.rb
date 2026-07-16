class IndicatorService
  def initialize(candles)
    @candles = candles
    @closes  = candles.map { |c| c.close.to_f }
    @volumes = candles.map { |c| c.volume.to_f }
  end

  def sma(period: 50)
    return nil if @closes.length < period
    @closes.last(period).sum / period.to_f
  end

  def average_volume(period: 20)
    return nil if @volumes.length < period
    @volumes.last(period).sum / period.to_f
  end

  def last_close  = @closes.last
  def last_volume = @volumes.last

  def ema_value(period: 50)
    series = ema(@closes, period)
    series.last
  end

  # ADX (Average Directional Index) — trend strength.
  #   ADX > 25 = strong trend, < 20 = ranging, 20-25 = transitioning
  # Returns { adx:, plus_di:, minus_di: } or nil.
  def adx(period: 14)
    return nil if @candles.length < period * 2 + 1

    plus_dm  = []
    minus_dm = []
    trs      = []

    @candles.each_cons(2) do |prev, curr|
      up_move   = curr.high.to_f - prev.high.to_f
      down_move = prev.low.to_f - curr.low.to_f
      plus_dm  << (up_move > down_move && up_move > 0 ? up_move : 0.0)
      minus_dm << (down_move > up_move && down_move > 0 ? down_move : 0.0)
      trs      << [ curr.high.to_f - curr.low.to_f, (curr.high.to_f - prev.close.to_f).abs, (curr.low.to_f - prev.close.to_f).abs ].max
    end

    # Wilder smoothing
    smooth = ->(series) {
      first = series.first(period).sum
      out = [ first ]
      series.drop(period).each { |v| out << (out.last - out.last / period.to_f + v) }
      out
    }

    sm_tr   = smooth.call(trs)
    sm_pdm  = smooth.call(plus_dm)
    sm_mdm  = smooth.call(minus_dm)

    plus_di_series  = sm_pdm.zip(sm_tr).map  { |p, t| t.zero? ? 0 : (p / t * 100) }
    minus_di_series = sm_mdm.zip(sm_tr).map { |m, t| t.zero? ? 0 : (m / t * 100) }

    dx_series = plus_di_series.zip(minus_di_series).map do |p, m|
      sum = p + m
      sum.zero? ? 0 : ((p - m).abs / sum * 100)
    end

    return nil if dx_series.length < period

    adx_first = dx_series.first(period).sum / period.to_f
    adx_val = adx_first
    dx_series.drop(period).each { |dx| adx_val = (adx_val * (period - 1) + dx) / period.to_f }

    {
      adx:      adx_val.round(2),
      plus_di:  plus_di_series.last.round(2),
      minus_di: minus_di_series.last.round(2)
    }
  end

  # Average True Range — volatility measure
  def atr(period: 14)
    return nil if @candles.length < period + 1

    trs = @candles.each_cons(2).map do |prev, curr|
      high = curr.high.to_f
      low  = curr.low.to_f
      prev_close = prev.close.to_f
      [ high - low, (high - prev_close).abs, (low - prev_close).abs ].max
    end

    # Wilder smoothing on TR
    avg = trs.first(period).sum / period.to_f
    trs.drop(period).each { |tr| avg = (avg * (period - 1) + tr) / period.to_f }
    avg
  end

  # ATR as percentage of price (volatility scaled)
  def atr_pct(period: 14)
    val = atr(period: period)
    return nil unless val
    last = last_close
    return nil if last.nil? || last.zero?
    (val / last * 100.0).round(3)
  end

  # Trend bias berdasarkan price vs EMA50 dan EMA50 vs EMA200.
  # Loosened: cukup price > EMA50 untuk bias bullish (gak harus ema50 > ema200).
  def trend_bias
    return :neutral if @closes.length < 50

    price = last_close
    ema50 = ema_value(period: 50)
    return :neutral if [ price, ema50 ].any?(&:nil?)

    ema200 = @closes.length >= 200 ? ema_value(period: 200) : nil

    # Primary direction from price vs ema50
    pct50 = (price - ema50) / ema50 * 100

    if pct50 > 0.3
      # Stronger bullish kalau ema50 > ema200 juga; tapi cukup pakai pct50 saja
      :bullish
    elsif pct50 < -0.3
      :bearish
    else
      :neutral
    end
  end

  # Same as trend_bias now — kept for backwards compat
  def short_trend_bias
    trend_bias
  end

  # Wilder smoothing RSI
  def rsi(period: 14)
    return nil if @closes.length < period + 1

    changes = @closes.each_cons(2).map { |a, b| b - a }
    gains = changes.map { |c| c > 0 ? c : 0.0 }
    losses = changes.map { |c| c < 0 ? -c : 0.0 }

    avg_gain = gains.first(period).sum / period
    avg_loss = losses.first(period).sum / period

    changes.drop(period).each_with_index do |_, i|
      avg_gain = (avg_gain * (period - 1) + gains[period + i]) / period
      avg_loss = (avg_loss * (period - 1) + losses[period + i]) / period
    end

    return 100.0 if avg_loss.zero?

    rs = avg_gain / avg_loss
    100.0 - (100.0 / (1.0 + rs))
  end

  def macd(fast: 12, slow: 26, signal: 9)
    return nil if @closes.length < slow + signal

    fast_ema  = ema(@closes, fast)
    slow_ema  = ema(@closes, slow)
    macd_line = fast_ema.last(slow_ema.length).zip(slow_ema).map { |f, s| f - s }

    signal_line = ema(macd_line, signal)
    histogram   = macd_line.last(signal_line.length).zip(signal_line).map { |m, s| m - s }

    {
      macd:           macd_line.last.round(8),
      signal:         signal_line.last.round(8),
      histogram:      histogram.last.round(8),
      prev_histogram: histogram[-2]&.round(8)
    }
  end

  # Bollinger Band width = (upper - lower) / middle, sebagai fraksi.
  # Kembalikan PERSENTIL (0-100) lebar bar ke-`offset`-dari-akhir vs `lookback` bar
  # yang berakhir di bar itu. Persentil rendah = squeeze (band tersempit dalam riwayat).
  # Return nil kalau data kurang.
  def bb_width_percentile(period: 20, lookback: 100, offset: 0)
    return nil if @closes.length < period + 1

    widths = []
    (period - 1...@closes.length).each do |i|
      window   = @closes[(i - period + 1)..i]
      mean     = window.sum / period
      next if mean.zero?
      variance = window.sum { |v| (v - mean)**2 } / period
      widths << (4.0 * Math.sqrt(variance)) / mean   # (upper-lower)/middle, std_dev=2 => 4*sd/mean
    end

    target = widths.length - 1 - offset
    return nil if target < 1

    sample  = widths[[ 0, target - lookback + 1 ].max..target]
    return nil if sample.length < 2

    current = widths[target]
    below   = sample.count { |w| w < current }
    (below.to_f / (sample.length - 1) * 100.0).round(2)
  end

  # Breakout dari range `lookback` bar SEBELUM bar berjalan.
  # close > high sebelumnya => :bullish; < low => :bearish; else nil.
  def range_breakout(lookback: 20)
    return nil if @candles.length < lookback + 1

    prior = @candles[-(lookback + 1)..-2]
    high  = prior.map { |c| c.high.to_f }.max
    low   = prior.map { |c| c.low.to_f }.min
    close = last_close

    if close > high
      { direction: :bullish, level: high.round(8) }
    elsif close < low
      { direction: :bearish, level: low.round(8) }
    end
  end

  def bollinger(period: 20, std_dev: 2)
    return nil if @closes.length < period

    window = @closes.last(period)
    mean   = window.sum / period
    variance = window.sum { |v| (v - mean)**2 } / period
    sd = Math.sqrt(variance)

    {
      upper:  (mean + std_dev * sd).round(8),
      middle: mean.round(8),
      lower:  (mean - std_dev * sd).round(8)
    }
  end

  private

  def ema(values, period)
    return [] if values.length < period

    k = 2.0 / (period + 1)
    result = [values.first(period).sum / period]

    values.drop(period).each do |v|
      result << v * k + result.last * (1 - k)
    end

    result
  end
end
