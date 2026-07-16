class SentimentFetcherJob < ApplicationJob
  queue_as :default

  FNG_URL = "https://api.alternative.me/fng/"

  def perform
    data = fetch_fng
    return unless data

    snapshot = SentimentSnapshot.new(
      fear_greed_value:          data["value"].to_i,
      fear_greed_classification: data["value_classification"],
      captured_at:               Time.current
    )

    snapshot.composite_score = SentimentScoreService.new.call(snapshot)
    snapshot.save!
  rescue => e
    Rails.logger.error("[SentimentFetcherJob] #{e.class}: #{e.message}")
  end

  private

  def fetch_fng
    body = Http.get_json(FNG_URL, query: { limit: 1 })
    body.dig("data", 0)
  rescue => e
    Rails.logger.error("[SentimentFetcherJob] Fetch error: #{e.message}")
    nil
  end
end
