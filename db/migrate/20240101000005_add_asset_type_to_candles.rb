class AddAssetTypeToCandles < ActiveRecord::Migration[8.0]
  def change
    add_column :candles, :asset_type, :string, default: "crypto", null: false
    add_index :candles, :asset_type
    add_column :signals, :asset_type, :string, default: "crypto", null: false
    add_index :signals, :asset_type
  end
end
