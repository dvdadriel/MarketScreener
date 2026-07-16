require "cgi"

class YahooFinanceClient
  BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart"

  # Yahoo interval mapping (we use same labels as crypto for consistency)
  INTERVAL_MAP = {
    "1h" => "60m",
    "4h" => "1d",   # Yahoo doesn't support 4h for stocks; fall back to 1d
    "1d" => "1d"
  }.freeze

  RANGE_MAP = {
    "1h" => "1mo",
    "4h" => "6mo",
    "1d" => "1y"
  }.freeze

  # range: override rentang Yahoo (mis. "2y"/"5y"/"max") untuk backtest histori panjang.
  def klines(symbol:, interval:, limit: 200, range: nil)
    yahoo_interval = INTERVAL_MAP.fetch(interval, "1d")
    range        ||= RANGE_MAP.fetch(interval, "1y")

    # Encode simbol: "^JKSE" (indeks) punya "^" yang ilegal di URI mentah.
    json = Http.get_json(
      "#{BASE_URL}/#{CGI.escape(symbol)}",
      query:   { interval: yahoo_interval, range: range },
      headers: { "User-Agent" => "Mozilla/5.0" }
    )

    parse_chart(json, limit)
  rescue => e
    Rails.logger.error("[YahooFinanceClient] #{e.class}: #{e.message}")
    raise
  end

  private

  def parse_chart(json, limit)
    result = json.dig("chart", "result", 0)
    return [] unless result

    timestamps = result["timestamp"] || []
    quote      = result.dig("indicators", "quote", 0) || {}

    opens   = quote["open"]   || []
    highs   = quote["high"]   || []
    lows    = quote["low"]    || []
    closes  = quote["close"]  || []
    volumes = quote["volume"] || []

    rows = timestamps.each_with_index.map do |ts, i|
      next nil if opens[i].nil? || closes[i].nil?

      {
        opened_at: Time.at(ts).utc,
        open:      opens[i].to_d,
        high:      highs[i].to_d,
        low:       lows[i].to_d,
        close:     closes[i].to_d,
        volume:    (volumes[i] || 0).to_d
      }
    end.compact

    rows.last(limit)
  end
end
