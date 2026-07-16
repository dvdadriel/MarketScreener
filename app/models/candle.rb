class Candle < ApplicationRecord
  validates :symbol, :timeframe, :open, :high, :low, :close, :volume, :opened_at, presence: true
  validates :timeframe, inclusion: { in: %w[5m 15m 1h 4h 1d] }

  scope :for_symbol, ->(sym) { where(symbol: sym) }
  scope :for_timeframe, ->(tf) { where(timeframe: tf) }
  scope :for_asset, ->(type) { where(asset_type: type) }
  scope :crypto, -> { where(asset_type: "crypto") }
  scope :stock,  -> { where(asset_type: "stock") }
  scope :ordered, -> { order(opened_at: :asc) }
  scope :latest_per_symbol, -> {
    select("DISTINCT ON (symbol) *").order("symbol, opened_at DESC")
  }

  def self.latest_closes(timeframe: "1h", asset_type: "crypto")
    select("DISTINCT ON (symbol) symbol, close, opened_at, asset_type")
      .where(timeframe: timeframe, asset_type: asset_type)
      .order("symbol, opened_at DESC")
  end
end
