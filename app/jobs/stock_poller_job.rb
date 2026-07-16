class StockPollerJob < ApplicationJob
  queue_as :scan

  TIMEFRAMES = %w[1h 1d].freeze

  def perform(force: false)
    unless force || IdxMarket.open_now?
      Rails.logger.info("[StockPollerJob] IDX market closed, skipping")
      return
    end

    client = YahooFinanceClient.new
    universe = IdxUniverseService.all
    Rails.logger.info("[StockPollerJob] Polling #{universe.size} tickers × #{TIMEFRAMES.size} timeframes")

    success = 0
    failed = 0

    catch(:rate_limited) do
      universe.each_with_index do |symbol, i|
        TIMEFRAMES.each do |tf|
          begin
            rows = client.klines(symbol: symbol, interval: tf, limit: 200)
            upsert_candles(symbol, tf, rows)
            success += 1
          rescue Http::RetryableError => e
            Rails.logger.warn("[StockPollerJob] aborting batch (#{e.message})")
            throw :rate_limited
          rescue => e
            failed += 1
            Rails.logger.error("[StockPollerJob] #{symbol}/#{tf}: #{e.message}") if failed <= 10
          end

          sleep 0.2
        end

        # Throttle hindari rate limit Yahoo: pause 1s setiap 50 tickers
        sleep 1.0 if i.positive? && (i % 50).zero?
      end
    end

    Rails.logger.info("[StockPollerJob] Done. Success: #{success}, Failed: #{failed}")
    SignalEvaluatorJob.perform_later(asset_type: "stock")
  end

  private

  def upsert_candles(symbol, timeframe, rows)
    return if rows.empty?

    records = rows.map do |k|
      {
        symbol:     symbol,
        timeframe:  timeframe,
        asset_type: "stock",
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
