# Tracks BTC market regime to gate alt-BUY signals.
# Aturan:
#   - BTC drop >3% dalam 1 jam terakhir → block semua alt BUY (cuma BTCUSDT yang lolos)
#   - BTC drop >5% dalam 4 jam → block alt BUY juga
#   - Saat panic / dump, alt akan ikut jatuh; entry alt jadi catching falling knife
class BtcMarketState
  HOURLY_DUMP_PCT = -3.0
  FOUR_HOUR_DUMP_PCT = -5.0
  CACHE_KEY = "btc_market_state"
  CACHE_TTL = 5.minutes

  def self.alt_buy_blocked?(symbol)
    return false if symbol == "BTCUSDT"
    state = current_state
    state[:alt_buys_blocked]
  end

  def self.current_state
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { compute_state }
  end

  def self.compute_state
    hourly_change = price_change_pct("1h", lookback: 1)
    four_hour_change = price_change_pct("4h", lookback: 1)

    blocked = (hourly_change.present? && hourly_change <= HOURLY_DUMP_PCT) ||
              (four_hour_change.present? && four_hour_change <= FOUR_HOUR_DUMP_PCT)

    {
      alt_buys_blocked:  blocked,
      hourly_change:     hourly_change&.round(2),
      four_hour_change:  four_hour_change&.round(2),
      reason: if blocked
        "BTC dump #{hourly_change&.round(1)}% (1h) / #{four_hour_change&.round(1)}% (4h)"
      else
        "BTC stable"
      end,
      checked_at: Time.current
    }
  end

  def self.price_change_pct(timeframe, lookback: 1)
    candles = Candle.crypto.for_symbol("BTCUSDT").for_timeframe(timeframe).order(opened_at: :desc).limit(lookback + 1)
    return nil if candles.length < 2

    current = candles.first.close.to_f
    past    = candles.last.close.to_f
    return nil if past.zero?

    (current - past) / past * 100.0
  end
end
