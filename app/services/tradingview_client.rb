require "json"

# Public TradingView scanner (adapted from the tradingview-screener approach used
# by github.com/atilaahmettaner/tradingview-mcp). One batch POST per asset_type.
# Degrades to nil on any failure, like YahooFinanceClient/NvidiaNimClient.
class TradingViewClient
  BASE    = "https://scanner.tradingview.com".freeze
  COLUMNS = %w[Recommend.All Recommend.MA RSI close change volume].freeze

  # symbols: our internal symbols (e.g. "BTCUSDT", "BBCA.JK")
  # => { our_symbol => { recommend:, rsi:, change: } }, or nil on failure.
  def rating(symbols:, asset_type:)
    return {} if symbols.empty?

    market     = asset_type == "stock" ? "indonesia" : "crypto"
    ticker_map = symbols.to_h { |s| [ ticker(s, asset_type), s ] } # tv_ticker => our_symbol

    resp = Http.post_json(
      "#{BASE}/#{market}/scan",
      { symbols: { tickers: ticker_map.keys }, columns: COLUMNS },
      headers: { "User-Agent" => "Mozilla/5.0" }, # ponytail: TV 403s bare requests; swap to a rotating UA only if it starts blocking
      open_timeout: 10 # CloudFront connect from ID can exceed the 5s default; best-effort so a roomy connect beats losing the rating
    )
    rows = JSON.parse(resp.body)["data"] || []

    rows.each_with_object({}) do |row, acc|
      our = ticker_map[row["s"]]
      next unless our
      d = row["d"] || []
      acc[our] = { recommend: recommend_label(d[0]), rsi: d[2]&.round(2), change: d[4]&.round(2) }
    end
  rescue Http::Error, JSON::ParserError => e
    Rails.logger.warn("[TradingViewClient] #{e.class}: #{e.message}")
    nil
  end

  private

  def ticker(symbol, asset_type)
    if asset_type == "stock"
      "IDX:#{symbol.sub(/\.JK\z/, '')}"
    else
      "BINANCE:#{symbol}"
    end
  end

  def recommend_label(val)
    return "NEUTRAL" if val.nil?
    case val
    when 0.5..Float::INFINITY then "STRONG_BUY"
    when 0.1...0.5            then "BUY"
    when -0.1...0.1           then "NEUTRAL"
    when -0.5...-0.1          then "SELL"
    else                           "STRONG_SELL"
    end
  end
end
