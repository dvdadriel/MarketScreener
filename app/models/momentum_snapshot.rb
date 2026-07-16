# Snapshot harian hasil MomentumRankingService — data forward-tracking untuk
# membuktikan (atau membantah) edge momentum. Satu baris per pick; hari risk-off
# dicatat satu baris marker (rank & symbol nil) supaya regime tetap terekam.
class MomentumSnapshot < ApplicationRecord
  scope :for_date, ->(d) { where(snapshot_date: d) }
  scope :picks,    -> { where.not(symbol: nil) }

  def self.snapshot_dates
    distinct.order(:snapshot_date).pluck(:snapshot_date)
  end

  def self.taken_for?(date)
    for_date(date).exists?
  end
end
