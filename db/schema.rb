# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_28_120100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "candles", force: :cascade do |t|
    t.string "asset_type", default: "crypto", null: false
    t.decimal "close", precision: 20, scale: 8, null: false
    t.datetime "created_at", null: false
    t.decimal "high", precision: 20, scale: 8, null: false
    t.decimal "low", precision: 20, scale: 8, null: false
    t.decimal "open", precision: 20, scale: 8, null: false
    t.datetime "opened_at", null: false
    t.string "symbol", null: false
    t.string "timeframe", null: false
    t.datetime "updated_at", null: false
    t.decimal "volume", precision: 30, scale: 8, null: false
    t.index ["asset_type"], name: "index_candles_on_asset_type"
    t.index ["symbol", "timeframe", "opened_at"], name: "index_candles_on_symbol_timeframe_opened_at", unique: true
    t.index ["symbol", "timeframe"], name: "index_candles_on_symbol_and_timeframe"
  end

  create_table "momentum_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "momentum", precision: 10, scale: 4
    t.decimal "price", precision: 20, scale: 8
    t.integer "rank"
    t.string "regime", null: false
    t.date "snapshot_date", null: false
    t.string "symbol"
    t.datetime "updated_at", null: false
    t.index ["snapshot_date", "rank"], name: "index_momentum_snapshots_on_snapshot_date_and_rank", unique: true
    t.index ["snapshot_date"], name: "index_momentum_snapshots_on_snapshot_date"
  end

  create_table "momentum_tracker_summaries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "updated_at", null: false
  end

  create_table "paper_trade_stats_summaries", force: :cascade do |t|
    t.string "asset_type", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["asset_type"], name: "index_paper_trade_stats_summaries_on_asset_type", unique: true
  end

  create_table "paper_trades", force: :cascade do |t|
    t.string "asset_type", default: "crypto", null: false
    t.datetime "created_at", null: false
    t.decimal "current_pnl_pct", precision: 10, scale: 4
    t.decimal "current_price", precision: 20, scale: 8
    t.datetime "entry_at", null: false
    t.decimal "entry_price", precision: 20, scale: 8, null: false
    t.datetime "exit_at"
    t.decimal "exit_price", precision: 20, scale: 8
    t.string "exit_reason"
    t.datetime "last_updated_at"
    t.decimal "max_gain_pct", precision: 10, scale: 4
    t.integer "max_hours"
    t.decimal "max_loss_pct", precision: 10, scale: 4
    t.jsonb "metadata", default: {}
    t.decimal "pnl_pct", precision: 10, scale: 4
    t.string "side", null: false
    t.decimal "sl_pct", precision: 6, scale: 4
    t.string "status", default: "open", null: false
    t.string "strategy", null: false
    t.string "symbol", null: false
    t.string "timeframe"
    t.decimal "tp_pct", precision: 6, scale: 4
    t.bigint "trading_signal_id", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_type"], name: "index_paper_trades_on_asset_type"
    t.index ["exit_at"], name: "index_paper_trades_on_exit_at"
    t.index ["status"], name: "index_paper_trades_on_status"
    t.index ["strategy"], name: "index_paper_trades_on_strategy"
    t.index ["symbol", "status"], name: "index_paper_trades_on_symbol_and_status"
    t.index ["trading_signal_id"], name: "index_paper_trades_on_trading_signal_id"
  end

  create_table "sentiment_snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.integer "composite_score"
    t.datetime "created_at", null: false
    t.string "fear_greed_classification"
    t.integer "fear_greed_value"
    t.datetime "updated_at", null: false
    t.index ["captured_at"], name: "index_sentiment_snapshots_on_captured_at"
  end

  create_table "signals", force: :cascade do |t|
    t.boolean "alerted", default: false, null: false
    t.string "asset_type", default: "crypto", null: false
    t.datetime "created_at", null: false
    t.datetime "fired_at", null: false
    t.jsonb "metadata", default: {}
    t.decimal "score", precision: 5, scale: 4
    t.string "signal_type"
    t.string "strategy", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["alerted"], name: "index_signals_on_alerted"
    t.index ["asset_type"], name: "index_signals_on_asset_type"
    t.index ["fired_at"], name: "index_signals_on_fired_at"
    t.index ["symbol", "fired_at"], name: "index_signals_on_symbol_and_fired_at"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  add_foreign_key "paper_trades", "signals", column: "trading_signal_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
