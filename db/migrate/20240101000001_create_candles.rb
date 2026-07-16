class CreateCandles < ActiveRecord::Migration[8.0]
  def change
    create_table :candles do |t|
      t.string   :symbol,    null: false
      t.string   :timeframe, null: false
      t.decimal  :open,      precision: 20, scale: 8, null: false
      t.decimal  :high,      precision: 20, scale: 8, null: false
      t.decimal  :low,       precision: 20, scale: 8, null: false
      t.decimal  :close,     precision: 20, scale: 8, null: false
      t.decimal  :volume,    precision: 30, scale: 8, null: false
      t.datetime :opened_at, null: false
      t.timestamps
    end

    add_index :candles, [:symbol, :timeframe, :opened_at], unique: true
    add_index :candles, [:symbol, :timeframe]
  end
end
