class AddAnonReadPoliciesForDashboard < ActiveRecord::Migration[8.1]
  TABLES = %w[
    signals
    paper_trades
    candles
    momentum_tracker_summaries
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
      execute <<~SQL
        CREATE POLICY anon_read_#{table} ON public.#{table}
          FOR SELECT TO anon USING (true);
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
