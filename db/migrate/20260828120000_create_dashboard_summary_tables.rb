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

    execute <<~SQL
      CREATE VIEW latest_candle_closes AS
      SELECT DISTINCT ON (symbol, timeframe, asset_type)
        symbol, timeframe, asset_type, close, opened_at
      FROM candles
      ORDER BY symbol, timeframe, asset_type, opened_at DESC;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS latest_candle_closes;"
    drop_table :paper_trade_stats_summaries
    drop_table :momentum_tracker_summaries
  end
end
