class CreateMomentumSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :momentum_snapshots do |t|
      t.date    :snapshot_date, null: false
      t.string  :regime,        null: false            # "risk_on" | "risk_off"
      t.integer :rank                                   # nil pada marker risk-off
      t.string  :symbol                                 # nil pada marker risk-off
      t.decimal :momentum, precision: 10, scale: 4
      t.decimal :price,    precision: 20, scale: 8
      t.timestamps
    end

    add_index :momentum_snapshots, :snapshot_date
    add_index :momentum_snapshots, [ :snapshot_date, :rank ], unique: true
  end
end
