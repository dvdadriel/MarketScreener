class IdxScannerJob < ApplicationJob
  queue_as :scan

  TOP_PICKS_LIMIT = 10

  def perform(skip_fetch: false)
    fetch_daily_candles unless skip_fetch

    picks = IdxScannerService.new.call.first(TOP_PICKS_LIMIT)

    save_picks(picks)
    send_telegram_picks(picks)

    Rails.logger.info("[IdxScannerJob] Saved #{picks.size} swing picks")
    picks
  end

  private

  def fetch_daily_candles
    client = YahooFinanceClient.new
    universe = IdxUniverseService.all
    Rails.logger.info("[IdxScannerJob] Fetching #{universe.size} IDX tickers")

    failed = 0
    catch(:rate_limited) do
      universe.each_with_index do |symbol, i|
        begin
          rows = client.klines(symbol: symbol, interval: "1d", limit: 200)
          upsert(symbol, rows)
        rescue Http::RetryableError => e
          Rails.logger.warn("[IdxScannerJob] aborting fetch (#{e.message})")
          throw :rate_limited
        rescue => e
          failed += 1
          Rails.logger.error("[IdxScannerJob] fetch #{symbol}: #{e.message}") if failed <= 20
        end

        # Throttle: 200ms between requests, extra 1s every 50 requests
        sleep 0.2
        sleep 1.0 if i.positive? && (i % 50).zero?
      end
    end

    Rails.logger.info("[IdxScannerJob] Fetch complete. Failed: #{failed}/#{universe.size}")
  end

  def upsert(symbol, rows)
    return if rows.empty?

    records = rows.map do |k|
      {
        symbol:     symbol,
        timeframe:  "1d",
        asset_type: "stock",
        open: k[:open], high: k[:high], low: k[:low], close: k[:close], volume: k[:volume],
        opened_at:  k[:opened_at],
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    Candle.upsert_all(
      records,
      unique_by: [ :symbol, :timeframe, :opened_at ],
      update_only: [ :open, :high, :low, :close, :volume, :asset_type ]
    )
  end

  def save_picks(picks)
    picks.each_with_index do |p, idx|
      TradingSignal.create!(
        symbol:      p[:symbol],
        signal_type: "BUY",
        strategy:    "SWING_PICK",
        score:       p[:composite_score] / 100.0,
        asset_type:  "stock",
        fired_at:    Time.current,
        alerted:     true,   # don't double-send via AlertDispatcherJob
        metadata: {
          rank:           idx + 1,
          rsi:            p[:rsi],
          macd_hist:      p[:macd_hist],
          macd_rising:    p[:macd_rising],
          last_close:     p[:last_close],
          ma50:           p[:ma50],
          price_vs_ma50:  p[:price_vs_ma50],
          volume_ratio:   p[:volume_ratio],
          breakdown:      p[:breakdown],
          timeframe:      "1d"
        }
      )
    rescue => e
      Rails.logger.error("[IdxScannerJob] save #{p[:symbol]}: #{e.message}")
    end
  end

  def send_telegram_picks(picks)
    return if picks.empty?

    notifier = TelegramNotifier.new(asset_type: "stock")
    return unless notifier.send(:configured?)

    date = Time.current.in_time_zone(IdxMarket::TZ).strftime("%Y-%m-%d")
    lines = [ "📈 *IDX Swing Picks — #{date}*", "" ]

    picks.each_with_index do |p, idx|
      sym = p[:symbol].sub(".JK", "")
      lines << "*#{idx + 1}. #{sym}* — Score *#{p[:composite_score]}*"
      lines << "  RSI: `#{p[:rsi]}` | MACD hist: `#{p[:macd_hist].round(2)}`#{p[:macd_rising] ? ' ↑' : ''}"
      lines << "  Price: Rp #{p[:last_close].to_i} (#{p[:price_vs_ma50] > 0 ? '+' : ''}#{p[:price_vs_ma50]}% vs MA50)"
      lines << "  Vol: #{p[:volume_ratio]}x avg"
      lines << ""
    end

    notifier.send(:post_message, lines.join("\n"))
  end
end
