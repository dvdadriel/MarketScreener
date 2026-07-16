class CreateSignals < ActiveRecord::Migration[8.0]
  def change
    create_table :signals do |t|
      t.string   :symbol,      null: false
      t.string   :signal_type
      t.string   :strategy,    null: false
      t.decimal  :score,       precision: 5, scale: 4
      t.jsonb    :metadata,    default: {}
      t.boolean  :alerted,     default: false, null: false
      t.datetime :fired_at,    null: false
      t.timestamps
    end

    add_index :signals, [:symbol, :fired_at]
    add_index :signals, :alerted
    add_index :signals, :fired_at
  end
end
