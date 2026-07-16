class CreatePaperTrades < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_trades do |t|
      t.references :trading_signal, foreign_key: { to_table: :signals }, index: true, null: false

      t.string  :symbol,      null: false
      t.string  :asset_type,  null: false, default: "crypto"
      t.string  :side,        null: false   # BUY or SELL
      t.string  :strategy,    null: false
      t.string  :timeframe

      t.decimal :entry_price,   precision: 20, scale: 8, null: false
      t.datetime :entry_at,     null: false

      t.decimal :current_price, precision: 20, scale: 8
      t.datetime :last_updated_at

      t.decimal :exit_price,   precision: 20, scale: 8
      t.datetime :exit_at
      t.string  :exit_reason          # take_profit, stop_loss, time_limit, manual

      t.decimal :pnl_pct,       precision: 10, scale: 4    # final P&L %
      t.decimal :current_pnl_pct, precision: 10, scale: 4  # live P&L while open
      t.decimal :max_gain_pct,  precision: 10, scale: 4
      t.decimal :max_loss_pct,  precision: 10, scale: 4

      t.decimal :sl_pct, precision: 6, scale: 4   # stop loss threshold
      t.decimal :tp_pct, precision: 6, scale: 4   # take profit threshold
      t.integer :max_hours                         # time limit

      t.string  :status, null: false, default: "open"  # open or closed

      t.jsonb   :metadata, default: {}
      t.timestamps
    end

    add_index :paper_trades, [ :symbol, :status ]
    add_index :paper_trades, :status
    add_index :paper_trades, :asset_type
    add_index :paper_trades, :strategy
    add_index :paper_trades, :exit_at
  end
end
