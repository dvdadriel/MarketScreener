class BinanceClient
  BASE_URL = "https://api.binance.com/api/v3/klines"

  def klines(symbol:, interval:, limit: 200)
    raw = Http.get_json(BASE_URL, query: { symbol: symbol, interval: interval, limit: limit })

    raw.map do |k|
      {
        opened_at: Time.at(k[0] / 1000.0).utc,
        open:      k[1].to_d,
        high:      k[2].to_d,
        low:       k[3].to_d,
        close:     k[4].to_d,
        volume:    k[5].to_d
      }
    end
  rescue => e
    Rails.logger.error("[BinanceClient] #{e.class}: #{e.message}")
    raise
  end
end
