class CandlePruneJob < ApplicationJob
  queue_as :default

  # How long to keep candles per timeframe. Lower timeframes generate far more
  # rows and lose value quickly; higher timeframes are cheap and useful longer.
  RETENTION = {
    "5m"  => 30.days,
    "15m" => 60.days,
    "1h"  => 180.days,
    "4h"  => 1.year,
    "1d"  => 3.years
  }.freeze

  def perform
    total = 0

    RETENTION.each do |timeframe, window|
      cutoff = window.ago
      deleted = Candle.where(timeframe: timeframe)
                      .where(opened_at: ...cutoff)
                      .delete_all
      total += deleted
      Rails.logger.info("[CandlePruneJob] #{timeframe}: deleted #{deleted} candles older than #{cutoff.to_date}") if deleted.positive?
    end

    Rails.logger.info("[CandlePruneJob] Done. Total deleted: #{total}")
    total
  end
end
