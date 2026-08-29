require "test_helper"

class StructureSqlTest < ActiveSupport::TestCase
  setup do
    @sql = File.read(Rails.root.join("db/structure.sql"))
  end

  test "RLS is enabled on the dashboard tables" do
    %w[signals paper_trades candles momentum_tracker_summaries paper_trade_stats_summaries].each do |table|
      assert_match(/ALTER TABLE public\.#{table}\s+ENABLE ROW LEVEL SECURITY/, @sql,
                   "expected RLS enabled on #{table}")
    end
  end

  test "anon read policies exist for the dashboard tables" do
    %w[signals paper_trades candles momentum_tracker_summaries paper_trade_stats_summaries].each do |table|
      assert_match(/CREATE POLICY anon_read_#{table} ON public\.#{table}/, @sql,
                   "expected anon_read_#{table} policy")
    end
  end

  test "anon has GRANT SELECT on dashboard tables and the latest_candle_closes view" do
    %w[signals paper_trades candles momentum_tracker_summaries paper_trade_stats_summaries latest_candle_closes].each do |table|
      assert_match(/GRANT SELECT ON TABLE public\.#{table} TO anon/, @sql,
                   "expected GRANT SELECT ... TO anon on #{table}")
    end
  end

  test "latest_candle_closes view filters to stock" do
    assert_match(/CREATE VIEW public\.latest_candle_closes/, @sql)
    assert_match(/WHERE.*\(\(candles\.asset_type\).*=.*'stock'/, @sql)
  end
end
