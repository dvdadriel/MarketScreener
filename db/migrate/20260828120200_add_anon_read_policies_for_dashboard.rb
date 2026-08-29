class AddAnonReadPoliciesForDashboard < ActiveRecord::Migration[8.1]
  TABLES = %w[
    signals
    paper_trades
    candles
    momentum_tracker_summaries
    paper_trade_stats_summaries
  ].freeze

  # Tables that carry an `asset_type` column and must be scoped to
  # "stock" rows only — the dashboard is stock-only post-pivot, but
  # historical "crypto" rows may still exist and must never be exposed
  # through the public anon key. `momentum_tracker_summaries` has no
  # asset_type column (it's an inherently stock-only singleton per
  # DashboardSummaryMaterializer), so it keeps an unscoped USING (true).
  STOCK_SCOPED_TABLES = %w[
    signals
    paper_trades
    candles
    paper_trade_stats_summaries
  ].freeze

  def up
    TABLES.each do |table|
      # GRANT dulu — RLS policy mengatur baris mana yang boleh dibaca, tapi
      # tanpa GRANT SELECT, role anon tidak boleh menyentuh tabelnya sama
      # sekali. Supabase biasa nge-set default privileges ini otomatis untuk
      # tabel yang dibuat lewat dashboard-nya; karena di sini tabel dibuat
      # lewat migrasi Rails yang connect langsung, GRANT eksplisit lebih aman
      # daripada mengandalkan default privileges yang mungkin belum ke-set.
      execute "GRANT SELECT ON public.#{table} TO anon;"
      using_clause = STOCK_SCOPED_TABLES.include?(table) ? "asset_type = 'stock'" : "true"
      execute <<~SQL
        CREATE POLICY anon_read_#{table} ON public.#{table}
          FOR SELECT TO anon USING (#{using_clause});
      SQL
    end
    execute "GRANT SELECT ON public.latest_candle_closes TO anon;"
  end

  def down
    TABLES.each do |table|
      execute "DROP POLICY IF EXISTS anon_read_#{table} ON public.#{table};"
      execute "REVOKE SELECT ON public.#{table} FROM anon;"
    end
    execute "REVOKE SELECT ON public.latest_candle_closes FROM anon;"
  end
end
