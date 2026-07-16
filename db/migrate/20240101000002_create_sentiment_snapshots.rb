class CreateSentimentSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :sentiment_snapshots do |t|
      t.integer  :fear_greed_value
      t.string   :fear_greed_classification
      t.integer  :composite_score
      t.datetime :captured_at, null: false
      t.timestamps
    end

    add_index :sentiment_snapshots, :captured_at
  end
end
