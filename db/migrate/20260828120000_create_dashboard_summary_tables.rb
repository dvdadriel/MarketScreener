class CreateDashboardSummaryTables < ActiveRecord::Migration[8.1]
  def up
    create_table :momentum_tracker_summaries do |t|
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    create_table :paper_trade_stats_summaries do |t|
      t.string :asset_type, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :paper_trade_stats_summaries, :asset_type, unique: true

    # Postgres views run with the *owner's* privileges by default, not the
    # querying role's — so scoping the anon_read_candles RLS policy on
    # `candles` alone would NOT restrict this view; anon could still read
    # every asset_type through it. `security_invoker` (PG 15+) would fix
    # that, but the target Postgres here is 14, so instead the stock-only
    # filter is baked directly into the view definition. This is also more
    # robust than relying on invoker semantics: the view is correct
    # regardless of who queries it or how the underlying table's RLS
    # policies change in the future.
    execute <<~SQL
      CREATE VIEW latest_candle_closes AS
      SELECT DISTINCT ON (symbol, timeframe, asset_type)
        symbol, timeframe, asset_type, close, opened_at
      FROM candles
      WHERE asset_type = 'stock'
      ORDER BY symbol, timeframe, asset_type, opened_at DESC;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS latest_candle_closes;"
    drop_table :paper_trade_stats_summaries
    drop_table :momentum_tracker_summaries
  end
end
