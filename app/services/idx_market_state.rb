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
  CACHE_KEY = "idx_market_state".freeze
  CACHE_TTL = 1.hour
  DEGRADED_TTL   = 5.minutes
  LAST_KNOWN_KEY = "idx_market_state:last_known".freeze
  LAST_KNOWN_TTL = 3.days

  # Backtest bisa set Thread.current[:backtest_as_of] (Time) → regime dihitung dari
  # histori ^JKSE tersimpan (asset_type "index") sampai tanggal itu (as-of, tanpa
  # lookahead). Atau [:backtest_bypass_regime] → tak memblokir. Default: live.
  def self.long_blocked?
    if (t = Thread.current[:backtest_as_of])
      return regime_as_of(t)
    end
    return false if Thread.current[:backtest_bypass_regime]
    current_state[:long_blocked]
  end

  def self.ihsg_closes
    t = Thread.current[:backtest_as_of]
    t ? closes_as_of(t) : current_state[:closes]   # oldest -> newest, untuk relative strength (#5)
  end
  def self.reason        = current_state[:reason]

  def self.regime_as_of(date)
    closes = closes_as_of(date)
    return false if closes.length < 50   # fail-open: data kurang → jangan blokir
    last  = closes.last
    ma50  = avg(closes, 50)
    ma200 = avg(closes, 200)
    last < ma50 || (ma200 && ma50 < ma200)
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
    ma200 = avg(closes, 200)

    blocked = last < ma50 || (ma200 && ma50 < ma200)
    # Simpan regime terakhir yang sahih — fallback saat fetch berikutnya gagal.
    Rails.cache.write(LAST_KNOWN_KEY, { long_blocked: blocked, checked_at: Time.current },
                      expires_in: LAST_KNOWN_TTL)
    {
      long_blocked: blocked,
      closes:       closes,
      reason:       blocked ? "IHSG risk-off (close #{last.round} vs MA50 #{ma50&.round})" : "IHSG risk-on",
      checked_at:   Time.current
    }
  rescue => e
    Rails.logger.warn("[IdxMarketState] #{e.class}: #{e.message}")
    degraded_state(e.message)
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
