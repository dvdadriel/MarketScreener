class PricePollerJob < ApplicationJob
  queue_as :realtime

  TIMEFRAMES = %w[5m 15m 1h 4h 1d].freeze

  # Run a single timeframe per invocation — much shorter cycle, won't pile up.
  def perform(timeframe: "1h")
    client = BinanceClient.new
    success = 0
    failed = 0

    MarketScannerService.watchlist.each do |symbol|
      begin
        klines = client.klines(symbol: symbol, interval: timeframe, limit: 200)
        upsert_candles(symbol, timeframe, klines)
        success += 1
      rescue Http::RetryableError => e
        # Rate limited / upstream down: stop hammering, next schedule resumes.
        Rails.logger.warn("[PricePollerJob #{timeframe}] aborting batch (#{e.message})")
        break
      rescue => e
        failed += 1
        Rails.logger.error("[PricePollerJob #{timeframe}] #{symbol}: #{e.message}")
      end

      sleep 0.1
    end

    Rails.logger.info("[PricePollerJob #{timeframe}] Done. Success: #{success}, Failed: #{failed}")
    SignalEvaluatorJob.perform_later(asset_type: "crypto")
  end

  private

  def upsert_candles(symbol, timeframe, klines)
    return if klines.empty?

    records = klines.map do |k|
      {
        symbol:     symbol,
        timeframe:  timeframe,
        asset_type: "crypto",
        open:       k[:open],
        high:       k[:high],
        low:        k[:low],
        close:      k[:close],
        volume:     k[:volume],
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
end
