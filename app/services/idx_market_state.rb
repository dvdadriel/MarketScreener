# Regime pasar IHSG untuk gate BUY saham — padanan BtcMarketState di crypto.
# ~70-80% saham IDX bergerak searah IHSG; melawan regime = jalan tercepat rugi.
#
# Risk-off (long_blocked) kalau IHSG di bawah MA50, ATAU MA50 < MA200 (tren
# menengah rusak). Jangan buka long baru melawan indeks.
#
# Degradasi (plan #4, FAIL-CLOSED): kalau fetch ^JKSE gagal, pakai regime terakhir
# yang diketahui (last-known, tahan 3 hari — regime bergerak lambat). Tanpa
# last-known → BLOKIR entry baru (tanpa konfirmasi regime = jangan trading).
# Network blip tak boleh dianggap risk-on. State degraded di-cache 5 menit saja
# supaya pemulihan cepat; state sehat 1 jam.
class IdxMarketState
  SYMBOL    = "^JKSE".freeze
  # Histeresis anti-whipsaw jalur LIVE (plan H7, tervalidasi backtest 2y & 3y:
  # ret/alpha/maxDD semua membaik, tak pernah lebih buruk). Regime tak flip di
  # satu hari — perlu CONFIRM_DAYS hari bursa berturut-turut searah dulu.
  CONFIRM_DAYS = 5
  CACHE_KEY = "idx_market_state".freeze
  CACHE_TTL = 1.hour
  DEGRADED_TTL   = 5.minutes
  LAST_KNOWN_KEY = "idx_market_state:last_known".freeze
  LAST_KNOWN_TTL = 3.days

  # Backtest bisa set Thread.current[:backtest_as_of] (Time) → regime dihitung dari
  # histori ^JKSE tersimpan (asset_type "index") sampai tanggal itu (as-of, tanpa
  # lookahead). Atau [:backtest_bypass_regime] → tak memblokir. Default: live.
  #
  # Thread.current[:regime_confirm_days] (plan H7, hipotesis diuji backtest): kalau
  # >0, regime tak langsung flip di satu hari — perlu N hari bursa berturut-turut
  # searah sebelum berubah (anti-whipsaw). Default 0 = perilaku lama (flip instan).
  def self.long_blocked?
    if (t = Thread.current[:backtest_as_of])
      return regime_as_of(t, confirm_days: Thread.current[:regime_confirm_days].to_i)
    end
    return false if Thread.current[:backtest_bypass_regime]
    current_state[:long_blocked]
  end

  def self.ihsg_closes
    t = Thread.current[:backtest_as_of]
    t ? closes_as_of(t) : current_state[:closes]   # oldest -> newest, untuk relative strength (#5)
  end
  def self.reason        = current_state[:reason]

  def self.regime_as_of(date, confirm_days: 0)
    confirmed_blocked(closes_as_of(date), confirm_days)
  end

  # Regime blocked/tidak dengan histeresis. confirm_days=0 → raw (flip instan);
  # >0 → butuh N hari searah berturut-turut sebelum berubah. Dipakai jalur live
  # (CONFIRM_DAYS) maupun backtest as-of (thread-local).
  def self.confirmed_blocked(closes, confirm_days)
    return false if closes.length < 50   # fail-open: data kurang → jangan blokir
    return raw_blocked(closes) if confirm_days.zero?

    count = closes.length - 49   # jumlah hari yang punya MA50 computable
    apply_hysteresis(raw_series(closes, count), confirm_days)
  end

  def self.raw_blocked(closes)
    ma50 = avg(closes, 50)
    return false unless ma50
    ma200 = avg(closes, 200)
    closes.last < ma50 || (ma200 && ma50 < ma200)
  end

  # Raw blocked/tidak per hari untuk `count` hari terakhir (rolling MA50/MA200).
  def self.raw_series(closes, count)
    n = closes.length
    (0...count).map { |k| raw_blocked(closes[0..(n - count + k)]) }
  end

  # State machine: regime hanya flip kalau raw signal SAMA selama `confirm_days`
  # hari berturut-turut berlawanan dengan state terkonfirmasi saat ini.
  def self.apply_hysteresis(series, confirm_days)
    return series.last if series.size <= confirm_days
    state = series.first
    series.each_index do |i|
      next if i < confirm_days - 1
      window = series[(i - confirm_days + 1)..i]
      state = window.first if window.uniq.size == 1 && window.first != state
    end
    state
  end

  def self.closes_as_of(date)
    Candle.where(asset_type: "index", symbol: SYMBOL, timeframe: "1d")
          .where("opened_at <= ?", date).order(:opened_at)
          .pluck(:close).map(&:to_f).reject(&:zero?)
  end

  def self.current_state
    cached = Rails.cache.read(CACHE_KEY)
    return cached if cached

    state = compute_state
    ttl   = state[:degraded] ? DEGRADED_TTL : CACHE_TTL   # degraded → retry cepat
    Rails.cache.write(CACHE_KEY, state, expires_in: ttl)
    state
  end

  def self.compute_state
    rows   = YahooFinanceClient.new.klines(symbol: SYMBOL, interval: "1d", limit: 220)
    closes = rows.map { |k| k[:close].to_f }.reject(&:zero?)
    return degraded_state("IHSG data unavailable") if closes.length < 50

    last  = closes.last
    ma50  = avg(closes, 50)

    blocked = confirmed_blocked(closes, CONFIRM_DAYS)
    # Simpan regime terakhir yang sahih — fallback saat fetch berikutnya gagal.
    Rails.cache.write(LAST_KNOWN_KEY, { long_blocked: blocked, checked_at: Time.current },
                      expires_in: LAST_KNOWN_TTL)
    {
      long_blocked: blocked,
      closes:       closes,
      reason:       blocked ? "IHSG risk-off (#{block_reason(closes, last, ma50)})" : "IHSG risk-on",
      checked_at:   Time.current
    }
  rescue => e
    Rails.logger.warn("[IdxMarketState] #{e.class}: #{e.message}")
    degraded_state(e.message)
  end

  # Sebab risk-off sebenarnya: harga di bawah MA50, death cross (MA50<MA200), atau
  # histeresis masih menahan status risk-off lama (raw sudah tak blocked, tunggu konfirmasi).
  def self.block_reason(closes, last, ma50)
    ma200 = avg(closes, 200)
    if !raw_blocked(closes)
      "histeresis menahan, #{CONFIRM_DAYS}h konfirmasi"
    elsif last < ma50
      "close #{last.round} < MA50 #{ma50&.round}"
    elsif ma200 && ma50 < ma200
      "death cross: MA50 #{ma50&.round} < MA200 #{ma200.round}"
    else
      "risk-off"
    end
  end

  def self.avg(closes, n)
    closes.length >= n ? closes.last(n).sum / n.to_f : nil
  end

  # Fetch gagal: last-known dulu (regime lambat berubah, 3 hari masih relevan);
  # tanpa last-known → FAIL-CLOSED: blokir entry baru sampai regime terkonfirmasi.
  def self.degraded_state(reason)
    last = Rails.cache.read(LAST_KNOWN_KEY)
    if last
      age_h = ((Time.current - last[:checked_at]) / 3600).round
      { long_blocked: last[:long_blocked], closes: [], degraded: true,
        reason: "last-known #{last[:long_blocked] ? 'risk-off' : 'risk-on'} #{age_h}j lalu (fetch gagal: #{reason})",
        checked_at: Time.current }
    else
      { long_blocked: true, closes: [], degraded: true,
        reason: "fail-closed: regime tak terkonfirmasi (#{reason})", checked_at: Time.current }
    end
  end
end
