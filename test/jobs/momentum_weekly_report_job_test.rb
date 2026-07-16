require "test_helper"

class MomentumWeeklyReportJobTest < ActiveSupport::TestCase
  def stub_notifier(configured: true)
    sent = []
    TelegramNotifier.class_eval do
      alias_method :__orig_configured?, :configured?
      alias_method :__orig_post_message, :post_message
      define_method(:configured?) { configured }
      define_method(:post_message) { |text| sent << text }
    end
    yield sent
  ensure
    TelegramNotifier.class_eval do
      alias_method :configured?, :__orig_configured?
      alias_method :post_message, :__orig_post_message
      remove_method :__orig_configured?, :__orig_post_message
    end
  end

  def seed_week
    d0 = Date.current - 8
    d1 = Date.current
    [ d0, d1 ].each_with_index do |d, i|
      MomentumSnapshot.create!(snapshot_date: d, regime: "risk_on", rank: 1,
                               symbol: "AAA.JK", momentum: 0.3, price: 100.0 + i * 10)
      Candle.create!(symbol: "AAA.JK", timeframe: "1d", asset_type: "stock",
                     open: 100, high: 100, low: 100, close: 100.0 + i * 10, volume: 1_000_000,
                     opened_at: d.to_time.utc)
    end
  end

  test "sends reconciliation message with paper vs IHSG and negative control" do
    seed_week
    stub_notifier do |sent|
      MomentumWeeklyReportJob.perform_now
      assert_equal 1, sent.size
      msg = sent.first
      assert_includes msg, "Rekonsiliasi Mingguan Momentum"
      assert_includes msg, "Kontrol negatif"
      assert_includes msg, "AAA"
    end
  end

  test "skips silently when no snapshots exist" do
    stub_notifier do |sent|
      MomentumWeeklyReportJob.perform_now
      assert_empty sent
    end
  end
end
