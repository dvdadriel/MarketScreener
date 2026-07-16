class MarketScannerService
  TICKER_URL = "https://api.binance.com/api/v3/ticker/24hr"

  CORE_SYMBOLS = %w[BTCUSDT ETHUSDT BNBUSDT SOLUSDT XRPUSDT].freeze

  STABLECOIN_BASES = %w[
    USDC BUSD TUSD USDP DAI FDUSD USDD PYUSD GUSD USTC FRAX LUSD
    EUR GBP AEUR EURI USD1
  ].freeze

  LEVERAGED_SUFFIXES = %w[UPUSDT DOWNUSDT BULLUSDT BEARUSDT].freeze

  TOP_N = 100
  CACHE_KEY = "market_scanner:watchlist"
  PREVIOUS_KEY = "market_scanner:watchlist:previous"
  SCANNED_AT_KEY = "market_scanner:scanned_at"
  CACHE_TTL = 1.hour

  def self.watchlist
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
      new_list = new.call
      detect_changes(new_list)
      Rails.cache.write(PREVIOUS_KEY, new_list, expires_in: 7.days)
      Rails.cache.write(SCANNED_AT_KEY, Time.current, expires_in: 7.days)
      new_list
    end
  end

  def self.refresh!
    Rails.cache.delete(CACHE_KEY)
    watchlist
  end

  def self.scanned_at
    Rails.cache.read(SCANNED_AT_KEY)
  end

  def self.detect_changes(new_list)
    previous = Rails.cache.read(PREVIOUS_KEY) || []
    return if previous.empty?

    added   = new_list - previous
    removed = previous - new_list

    return if added.empty? && removed.empty?

    TelegramNotifier.new.send_watchlist_change(added: added, removed: removed)
  rescue => e
    Rails.logger.error("[MarketScannerService] notify failed: #{e.message}")
  end

  def call
    pairs = fetch_tickers
    return CORE_SYMBOLS if pairs.empty?

    ranked = pairs
      .select { |t| usdt_pair?(t["symbol"]) }
      .reject { |t| stablecoin?(t["symbol"]) }
      .reject { |t| leveraged?(t["symbol"]) }
      .sort_by { |t| -t["quoteVolume"].to_f }
      .first(TOP_N)
      .map { |t| t["symbol"] }

    (CORE_SYMBOLS + ranked).uniq
  rescue => e
    Rails.logger.error("[MarketScannerService] #{e.class}: #{e.message}")
    CORE_SYMBOLS
  end

  private

  def fetch_tickers
    Http.get_json(TICKER_URL)
  rescue => e
    Rails.logger.error("[MarketScannerService] fetch failed: #{e.class}: #{e.message}")
    []
  end

  def usdt_pair?(symbol)
    symbol.end_with?("USDT") && symbol != "USDTUSDT"
  end

  def stablecoin?(symbol)
    base = symbol.sub(/USDT\z/, "")
    STABLECOIN_BASES.include?(base)
  end

  def leveraged?(symbol)
    LEVERAGED_SUFFIXES.any? { |s| symbol.end_with?(s) }
  end
end
