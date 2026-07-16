class DeepAnalysisService
  TF_CRYPTO = %w[15m 1h 4h 1d].freeze
  TF_STOCK  = %w[1h 1d].freeze

  def initialize(input)
    @input = input.to_s.strip.upcase
  end

  def call
    return error("Symbol required") if @input.empty?

    sym, asset_type = normalize_symbol
    timeframes = asset_type == "stock" ? TF_STOCK : TF_CRYPTO

    ensure_data_available(sym, asset_type, timeframes)

    per_tf = {}
    timeframes.each do |tf|
      candles = Candle.for_asset(asset_type).for_symbol(sym).for_timeframe(tf).ordered.last(220)
      per_tf[tf] = analyze_tf(candles)
    end

    valid_tf = per_tf.values.any? { |v| v[:has_data] }
    return error("No data available for #{sym}") unless valid_tf

    confluence = SignalConfluenceService.new(symbol: sym, asset_type: asset_type).evaluate

    result = {
      symbol:        sym,
      display:       display_name(sym, asset_type),
      asset_type:    asset_type,
      timeframes:    per_tf,
      confluence:    confluence,
      recommendation: build_recommendation(per_tf, confluence, asset_type),
      recent_signals: recent_signals(sym),
      paper_trades:  paper_trade_history(sym),
      analyzed_at:   Time.current
    }
    result[:narrative] = build_narrative(result)
    result
  rescue => e
    Rails.logger.error("[DeepAnalysisService] #{e.class}: #{e.message}")
    error(e.message)
  end

  private

  def normalize_symbol
    if @input.include?(".JK") || @input.match?(/\A[A-Z]{3,5}\z/)
      sym = @input.end_with?(".JK") ? @input : "#{@input}.JK"
      [ sym, "stock" ]
    elsif @input.end_with?("USDT")
      [ @input, "crypto" ]
    elsif @input.match?(/\A[A-Z]+\z/) && @input.length >= 3
      [ "#{@input}USDT", "crypto" ]
    else
      [ @input, "crypto" ]
    end
  end

  def display_name(sym, asset_type)
    asset_type == "stock" ? sym.sub(".JK", "") : sym
  end

  def ensure_data_available(sym, asset_type, timeframes)
    existing = Candle.for_asset(asset_type).for_symbol(sym).distinct.pluck(:timeframe)
    missing = timeframes - existing
    return if missing.empty?

    client = asset_type == "stock" ? YahooFinanceClient.new : BinanceClient.new

    missing.each do |tf|
      begin
        rows = client.klines(symbol: sym, interval: tf, limit: 200)
        records = rows.map do |k|
          {
            symbol: sym, timeframe: tf, asset_type: asset_type,
            open: k[:open], high: k[:high], low: k[:low], close: k[:close], volume: k[:volume],
            opened_at: k[:opened_at],
            created_at: Time.current, updated_at: Time.current
          }
        end
        next if records.empty?

        Candle.upsert_all(
          records,
          unique_by: [ :symbol, :timeframe, :opened_at ],
          update_only: [ :open, :high, :low, :close, :volume, :asset_type ]
        )
      rescue => e
        Rails.logger.warn("[DeepAnalysisService] fetch #{sym}/#{tf}: #{e.message}")
      end
    end
  end

  def analyze_tf(candles)
    if candles.length < 30
      return { has_data: false, candle_count: candles.length }
    end

    ind = IndicatorService.new(candles)
    rsi = ind.rsi
    macd = ind.macd
    bb = ind.bollinger
    last = candles.last
    prev = candles[-2]
    avg_vol = ind.average_volume(period: 20)
    ema50 = ind.ema_value(period: 50) if candles.length >= 50
    ema200 = ind.ema_value(period: 200) if candles.length >= 200
    atr = ind.atr
    atr_pct = ind.atr_pct
    trend = ind.trend_bias

    price_change_pct = prev ? ((last.close.to_f - prev.close.to_f) / prev.close.to_f * 100).round(2) : 0
    vol_ratio = avg_vol&.positive? ? (last.volume.to_f / avg_vol).round(2) : nil

    bb_position = if bb
      if last.close.to_f > bb[:upper] then "above upper"
      elsif last.close.to_f < bb[:lower] then "below lower"
      elsif last.close.to_f > bb[:middle] then "upper half"
      else "lower half"
      end
    end

    {
      has_data:        true,
      candle_count:    candles.length,
      last_close:      last.close.to_f,
      price_change:    price_change_pct,
      volume:          last.volume.to_f,
      volume_ratio:    vol_ratio,
      rsi:             rsi&.round(2),
      rsi_signal:      rsi_signal(rsi),
      macd_hist:       macd&.dig(:histogram)&.round(4),
      macd_rising:     macd && macd[:prev_histogram] && macd[:histogram] > macd[:prev_histogram],
      macd_signal:     macd_signal(macd),
      bb_upper:        bb&.dig(:upper)&.round(8),
      bb_middle:       bb&.dig(:middle)&.round(8),
      bb_lower:        bb&.dig(:lower)&.round(8),
      bb_position:     bb_position,
      ema50:           ema50&.round(4),
      ema200:          ema200&.round(4),
      vs_ema50_pct:    ema50 ? ((last.close.to_f - ema50) / ema50 * 100).round(2) : nil,
      vs_ema200_pct:   ema200 ? ((last.close.to_f - ema200) / ema200 * 100).round(2) : nil,
      atr:             atr&.round(8),
      atr_pct:         atr_pct,
      trend_bias:      trend,
      last_at:         last.opened_at
    }
  end

  def rsi_signal(rsi)
    return nil unless rsi
    case rsi
    when 0..25  then { dir: "BUY",     reason: "extreme oversold" }
    when 25..35 then { dir: "BUY",     reason: "oversold" }
    when 35..45 then { dir: "WATCH",   reason: "approaching oversold" }
    when 55..65 then { dir: "WATCH",   reason: "approaching overbought" }
    when 65..75 then { dir: "SELL",    reason: "overbought" }
    when 75..100 then { dir: "SELL",   reason: "extreme overbought" }
    else { dir: "NEUTRAL", reason: "mid-range" }
    end
  end

  def macd_signal(macd)
    return nil unless macd && macd[:prev_histogram]
    h = macd[:histogram]
    prev = macd[:prev_histogram]

    if h > 0 && h > prev
      { dir: "BUY", reason: "histogram positive & rising" }
    elsif h > 0 && h < prev
      { dir: "WATCH", reason: "positive but weakening" }
    elsif h < 0 && h < prev
      { dir: "SELL", reason: "histogram negative & falling" }
    elsif h < 0 && h > prev
      { dir: "WATCH", reason: "negative but improving" }
    else
      { dir: "NEUTRAL", reason: "no clear momentum" }
    end
  end

  def build_recommendation(per_tf, confluence, asset_type)
    if confluence
      meta = confluence[:metadata]
      return {
        verdict:    confluence[:signal_type],
        confidence: "HIGH",
        score:      (confluence[:score] * 100).round,
        reason:     "Confluence #{meta[:confluence]} indicators aligned, trend #{meta[:trend]}",
        entry:      meta[:entry_price],
        sl:         meta[:sl_price],
        tp:         meta[:tp_price],
        sl_pct:     meta[:sl_pct],
        tp_pct:     meta[:tp_pct],
        risk_reward: meta[:risk_reward]
      }
    end

    # Manual aggregation: count BUY/SELL signals across timeframes
    signals = per_tf.values.flat_map do |v|
      [ v[:rsi_signal]&.dig(:dir), v[:macd_signal]&.dig(:dir) ]
    end.compact

    buys  = signals.count("BUY")
    sells = signals.count("SELL")

    if buys >= 3 && sells == 0
      { verdict: "BUY",  confidence: "MEDIUM", reason: "#{buys} indicators bullish, no bearish" }
    elsif sells >= 3 && buys == 0
      { verdict: "SELL", confidence: "MEDIUM", reason: "#{sells} indicators bearish, no bullish" }
    elsif buys > sells
      { verdict: "WATCH-BUY", confidence: "LOW", reason: "#{buys} bullish vs #{sells} bearish — wait for confluence" }
    elsif sells > buys
      { verdict: "WATCH-SELL", confidence: "LOW", reason: "#{sells} bearish vs #{buys} bullish — wait for confluence" }
    else
      { verdict: "HOLD", confidence: "LOW", reason: "Mixed signals, no clear direction" }
    end
  end

  # Plain-language narration of the analysis via NVIDIA NIM. Optional: returns
  # nil (page still renders) when the LLM isn't configured or fails.
  def build_narrative(result)
    rec  = result[:recommendation] || {}
    conf = result[:confluence]
    summary = {
      symbol:     result[:display],
      verdict:    rec[:verdict],
      confidence: rec[:confidence],
      score:      rec[:score],
      reason:     rec[:reason],
      entry:      rec[:entry], sl: rec[:sl], tp: rec[:tp],
      confluence: conf && conf[:metadata]&.slice(:trend, :confluence, :atr_pct),
      per_tf:     result[:timeframes].filter_map { |tf, v|
        next unless v[:has_data]
        [ tf, { rsi: v[:rsi], rsi_signal: v[:rsi_signal]&.dig(:dir),
                macd: v[:macd_signal]&.dig(:dir), trend: v[:trend_bias],
                price_change: v[:price_change], vol_ratio: v[:volume_ratio] } ]
      }.to_h
    }

    NvidiaNimClient.new.chat(
      system: "Kamu analis trading. Jelaskan rekomendasi ini dalam 2-3 kalimat Bahasa Indonesia yang padat untuk trader ritel. Tanpa disclaimer, tanpa basa-basi.",
      user:   summary.to_json,
      timeout: 75   # cukup untuk DeepSeek (25-55s); fallback chain lanjut kalau lewat
    )
  rescue => e
    Rails.logger.warn("[DeepAnalysisService] narrative: #{e.message}")
    nil
  end

  def recent_signals(sym)
    TradingSignal.where(symbol: sym).order(fired_at: :desc).limit(10)
  end

  def paper_trade_history(sym)
    open   = PaperTrade.open_trades.where(symbol: sym).order(entry_at: :desc).limit(5)
    closed = PaperTrade.closed_trades.where(symbol: sym).order(exit_at: :desc).limit(10)

    {
      open: open,
      closed: closed,
      win_rate: closed.any? ? (closed.where("pnl_pct > 0").count.to_f / closed.count * 100).round(1) : nil,
      avg_pnl:  closed.average(:pnl_pct)&.to_f&.round(2)
    }
  end

  def error(msg)
    { error: msg }
  end
end
