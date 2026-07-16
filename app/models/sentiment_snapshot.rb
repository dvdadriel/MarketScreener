class SentimentSnapshot < ApplicationRecord
  validates :captured_at, presence: true
  validates :fear_greed_value, numericality: { in: 0..100 }, allow_nil: true
  validates :composite_score, numericality: { in: 0..100 }, allow_nil: true

  scope :recent, -> { order(captured_at: :desc) }

  def extreme_fear? = composite_score.present? && composite_score < 25
  def fear?         = composite_score.present? && composite_score < 45
  def greed?        = composite_score.present? && composite_score > 55
  def extreme_greed? = composite_score.present? && composite_score > 75

  def sentiment_label
    case composite_score
    when 0..24  then "Extreme Fear"
    when 25..44 then "Fear"
    when 45..55 then "Neutral"
    when 56..75 then "Greed"
    when 76..100 then "Extreme Greed"
    else "Unknown"
    end
  end

  def badge_color
    case composite_score
    when 0..24  then "bg-red-600"
    when 25..44 then "bg-orange-500"
    when 45..55 then "bg-yellow-400"
    when 56..75 then "bg-green-500"
    when 76..100 then "bg-emerald-600"
    else "bg-gray-400"
    end
  end
end
