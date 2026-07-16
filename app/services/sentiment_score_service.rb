class SentimentScoreService
  WEIGHTS = {
    fear_greed: 0.60,
    sopr:       0.40
  }.freeze

  def call(snapshot)
    fg_score   = snapshot.fear_greed_value
    sopr_score = nil # placeholder — wire in on-chain data when available

    if sopr_score.nil?
      # fall back to fear_greed only, rescale weight to 1.0
      return fg_score.to_i.clamp(0, 100)
    end

    weighted = fg_score * WEIGHTS[:fear_greed] + sopr_score * WEIGHTS[:sopr]
    weighted.round.clamp(0, 100)
  end
end
