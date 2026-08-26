require "test_helper"

class MomentumSnapshotBackfillServiceTest < ActiveSupport::TestCase
  def index_candle(date, close: 6000)
    Candle.create!(symbol: IdxMarketState::SYMBOL, timeframe: "1d", asset_type: "index",
                   open: close, high: close, low: close, close: close, volume: 1,
                   opened_at: Time.utc(date.year, date.month, date.day, 12))
  end

  test "does nothing when no snapshot has ever been recorded (fresh install)" do
    today = Time.current.in_time_zone(IdxMarket::TZ).to_date
    index_candle(today - 3)
    index_candle(today)
    assert_equal 0, MomentumSnapshotBackfillService.new.call
    assert_equal 0, MomentumSnapshot.count
  end

  test "fills gap days between last snapshot and today, leaves today untouched" do
    today = Time.current.in_time_zone(IdxMarket::TZ).to_date
    last  = today - 3
    gap   = today - 1

    [ last, gap, today ].each { |d| index_candle(d) }
    MomentumSnapshot.create!(snapshot_date: last, regime: "risk_on", rank: 1,
                             symbol: "AAA.JK", momentum: 0.1, price: 100)

    filled = MomentumSnapshotBackfillService.new.call

    assert_equal 1, filled
    assert MomentumSnapshot.taken_for?(gap)
    refute MomentumSnapshot.taken_for?(today), "backfill tak boleh menyentuh hari ini"
  end

  test "idempotent: does not duplicate already-backfilled days" do
    today = Time.current.in_time_zone(IdxMarket::TZ).to_date
    last  = today - 2
    gap   = today - 1
    [ last, gap, today ].each { |d| index_candle(d) }
    MomentumSnapshot.create!(snapshot_date: last, regime: "risk_on")

    MomentumSnapshotBackfillService.new.call
    second_run = MomentumSnapshotBackfillService.new.call

    assert_equal 0, second_run
  end

  test "returns the number of days actually RECORDED, not merely attempted" do
    today = Time.current.in_time_zone(IdxMarket::TZ).to_date
    last  = today - 4
    [ last, today - 3, today - 2, today - 1, today ].each { |d| index_candle(d) }
    MomentumSnapshot.create!(snapshot_date: last, regime: "risk_on")

    # Setiap hari gagal. backfill_day menelan exception dan hanya mencatat log,
    # jadi tanpa perbaikan `call` melaporkan 3 hari "berhasil" padahal nol.
    orig = MomentumRankingService.method(:new)
    MomentumRankingService.define_singleton_method(:new) { |**| raise "boom" }
    recorded = MomentumSnapshotBackfillService.new.call
  ensure
    MomentumRankingService.define_singleton_method(:new, orig)
    assert_equal 0, recorded, "call harus melaporkan hari yang TERCATAT, bukan yang dicoba"
    assert_equal 1, MomentumSnapshot.count, "hanya snapshot awal yang ada; tak ada yang tercatat"
  end

  test "counts only the days that succeed when some fail" do
    today = Time.current.in_time_zone(IdxMarket::TZ).to_date
    last  = today - 3
    [ last, today - 2, today - 1, today ].each { |d| index_candle(d) }
    MomentumSnapshot.create!(snapshot_date: last, regime: "risk_on")

    # Gagal hanya pada pemanggilan pertama, sukses pada sisanya.
    orig = MomentumRankingService.method(:new)
    calls = 0
    MomentumRankingService.define_singleton_method(:new) do |**kw|
      calls += 1
      raise "boom" if calls == 1
      orig.call(**kw)
    end
    recorded = MomentumSnapshotBackfillService.new.call
  ensure
    MomentumRankingService.define_singleton_method(:new, orig)
    assert_equal 1, recorded, "2 hari dicoba, 1 gagal, jadi 1 yang tercatat"
  end
end
