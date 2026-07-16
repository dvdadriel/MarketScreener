require "rexml/document"
require "cgi"

# Fetches recent news headlines via free RSS feeds. Returns [] on any failure —
# callers treat headlines as optional.
class NewsFetcher
  CRYPTO_FEEDS = [
    "https://www.coindesk.com/arc/outboundfeeds/rss/",
    "https://cointelegraph.com/rss"
  ].freeze
  MAX = 5

  def headlines(symbol:, asset_type:)
    titles = asset_type == "stock" ? stock_titles(symbol) : crypto_titles(symbol)
    titles.first(MAX)
  rescue Http::Error => e
    Rails.logger.warn("[NewsFetcher] #{symbol}: #{e.message}")
    []
  end

  private

  # Yahoo's RSS headline endpoint was retired (404). Google News RSS is free,
  # keyless, and gives Indonesian-language coverage for IDX tickers.
  def stock_titles(symbol)
    q = CGI.escape("#{symbol.sub(/\.JK\z/, '')} saham")
    url = "https://news.google.com/rss/search?q=#{q}&hl=id&gl=ID&ceid=ID:id"
    parse_titles(Http.get(url).body).drop(1)   # first <title> is "Google Berita"
  end

  def crypto_titles(symbol)
    base = symbol.sub(/USDT\z/, "")
    all = CRYPTO_FEEDS.flat_map do |url|
      parse_titles(Http.get(url).body).drop(1)
    rescue Http::Error
      []   # ponytail: one dead feed shouldn't sink the other
    end
    matched = all.select { |t| t.downcase.include?(base.downcase) }
    matched.any? ? matched : all
  end

  def parse_titles(xml)
    REXML::Document.new(xml)
      .get_elements("//item/title")
      .map { |e| e.text.to_s.strip }
      .reject(&:empty?)
  end
end
