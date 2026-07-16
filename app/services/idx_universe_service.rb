require "net/http"
require "json"

# Sumber daftar saham IDX. Prioritas:
#   1. File upload manual (storage/idx_universe.txt)
#   2. IDX official API (~900 listed companies)
#   3. Hardcoded fallback (~150 from IdxMarket::EXTENDED_WATCHLIST)
class IdxUniverseService
  IDX_API_URL  = "https://www.idx.co.id/primary/ListedCompany/GetCompanyProfilesGeneral".freeze
  CACHE_KEY    = "idx_universe:tickers".freeze
  CACHE_TTL    = 24.hours
  CUSTOM_FILE  = Rails.root.join("storage", "idx_universe.txt").freeze
  TIMEOUT_S    = 15

  def self.all
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.resolve }
  end

  def self.refresh!
    Rails.cache.delete(CACHE_KEY)
    all
  end

  def self.source
    return :custom if File.exist?(CUSTOM_FILE)
    Rails.cache.read("#{CACHE_KEY}:source") || :unknown
  end

  def self.custom_uploaded_at
    File.exist?(CUSTOM_FILE) ? File.mtime(CUSTOM_FILE) : nil
  end

  def self.save_custom(content)
    tickers = parse_input(content)
    raise "No valid tickers found" if tickers.empty?

    FileUtils.mkdir_p(File.dirname(CUSTOM_FILE))
    File.write(CUSTOM_FILE, tickers.join("\n"))
    Rails.cache.delete(CACHE_KEY)
    tickers
  end

  def self.clear_custom!
    File.delete(CUSTOM_FILE) if File.exist?(CUSTOM_FILE)
    Rails.cache.delete(CACHE_KEY)
  end

  def self.parse_input(content)
    content.to_s
           .split(/[\s,;]+/)
           .map(&:strip)
           .reject(&:empty?)
           .map { |t| t.upcase.end_with?(".JK") ? t.upcase : "#{t.upcase}.JK" }
           .uniq
           .sort
  end

  def resolve
    if File.exist?(CUSTOM_FILE)
      tickers = File.read(CUSTOM_FILE).split("\n").reject(&:empty?)
      if tickers.any?
        Rails.cache.write("#{CACHE_KEY}:source", :custom)
        return tickers
      end
    end

    api_tickers = fetch_from_idx
    if api_tickers.any?
      Rails.cache.write("#{CACHE_KEY}:source", :idx_api)
      return api_tickers
    end

    Rails.logger.warn("[IdxUniverseService] Falling back to hardcoded seed")
    Rails.cache.write("#{CACHE_KEY}:source", :hardcoded)
    IdxMarket::EXTENDED_WATCHLIST
  rescue => e
    Rails.logger.error("[IdxUniverseService] #{e.class}: #{e.message}")
    Rails.cache.write("#{CACHE_KEY}:source", :hardcoded)
    IdxMarket::EXTENDED_WATCHLIST
  end

  private

  def fetch_from_idx
    body = Http.get_json(
      IDX_API_URL,
      query: {
        draw: 1, start: 0, length: 1000,
        "search[value]" => "", "search[regex]" => "false"
      },
      headers: {
        "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36",
        "Accept"     => "application/json"
      },
      read_timeout: TIMEOUT_S
    )

    parse_response(body)
  rescue => e
    Rails.logger.error("[IdxUniverseService] Fetch failed: #{e.message}")
    []
  end

  def parse_response(body)
    data = body["data"] || []
    data.map { |row| row["KodeEmiten"] }.compact.uniq.map { |t| "#{t}.JK" }.sort
  end
end
