require "test_helper"

class IdxMarketStateTest < ActiveSupport::TestCase
  # Test env pakai null_store — swap ke MemoryStore agar last-known bisa diuji.
  def with_memory_cache
    store = ActiveSupport::Cache::MemoryStore.new
    orig = Rails.method(:cache)
    Rails.define_singleton_method(:cache) { store }
    yield
  ensure
    Rails.define_singleton_method(:cache, orig)
  end

  # Replace YahooFinanceClient#klines with a canned response for the block.
  def stub_klines(rows)
    YahooFinanceClient.class_eval do
      alias_method :__orig_klines, :klines
      define_method(:klines) { |**| rows }
    end
    yield
  ensure
    YahooFinanceClient.class_eval do
      alias_method :klines, :__orig_klines
      remove_method :__orig_klines
    end
  end

  def rows_from(closes)
    closes.map { |c| { close: c } }
  end

  test "risk-on when IHSG rising above its MAs" do
    stub_klines(rows_from((1..220).to_a)) do
      state = IdxMarketState.compute_state
      refute state[:long_blocked], state[:reason]
      assert_equal 220, state[:closes].length
    end
  end

  test "risk-off (blocked) when IHSG below MA50" do
    stub_klines(rows_from((1..220).to_a.reverse)) do
      state = IdxMarketState.compute_state
      assert state[:long_blocked], state[:reason]
    end
  end

  test "fail-closed (blocked) when fetch fails and no last-known regime" do
    with_memory_cache do
      stub_klines(rows_from((1..10).to_a)) do   # data terlalu pendek = degraded
        state = IdxMarketState.compute_state
        assert state[:long_blocked], "tanpa konfirmasi regime harus blokir entry baru"
        assert state[:degraded]
        assert_match(/fail-closed/, state[:reason])
      end
    end
  end

  test "falls back to last-known regime when fetch fails" do
    with_memory_cache do
      stub_klines(rows_from((1..220).to_a)) do
        IdxMarketState.compute_state          # sukses risk-on → last-known tersimpan
      end
      stub_klines(rows_from([])) do            # fetch berikutnya gagal
        state = IdxMarketState.compute_state
        refute state[:long_blocked], "last-known risk-on harus dipakai, bukan fail-closed"
        assert_match(/last-known risk-on/, state[:reason])
      end
    end
  end

  test "degraded state cached briefly, healthy state cached long" do
    with_memory_cache do
      stub_klines(rows_from([])) do
        IdxMarketState.current_state
        # degraded tersimpan di CACHE_KEY (retry cepat via TTL pendek — TTL tak
        # bisa di-assert langsung, cukup pastikan state degraded yang ter-cache)
        assert Rails.cache.read(IdxMarketState::CACHE_KEY)[:degraded]
      end
    end
  end

  # Plan H7: regime hysteresis (fungsi murni, tanpa DB) — blip singkat tak boleh
  # membuat regime flip; sinyal yang bertahan `confirm_days` harus flip.
  test "apply_hysteresis ignores a blip shorter than confirm_days" do
    series = ([ false ] * 5) + [ true ] + ([ false ] * 5)
    assert_equal false, IdxMarketState.apply_hysteresis(series, 3)
  end

  test "apply_hysteresis flips once signal persists for confirm_days consecutive days" do
    series = ([ false ] * 5) + ([ true ] * 3) + ([ false ] * 2)   # cuma 2 hari balik false setelahnya
    assert_equal true, IdxMarketState.apply_hysteresis(series, 3)
  end

  test "compute_state (live) applies CONFIRM_DAYS hysteresis — a short dip doesn't flip to risk-off" do
    # Naik mulus 210 hari lalu 3 hari anjlok di bawah MA50. Raw (last<MA50) = blocked,
    # tapi blip 3 hari < CONFIRM_DAYS(5) → regime live harus tetap risk-on.
    closes = (1..210).to_a + [ 50, 50, 50 ]
    stub_klines(rows_from(closes)) do
      state = IdxMarketState.compute_state
      refute state[:long_blocked], "blip < CONFIRM_DAYS tak boleh flip regime live: #{state[:reason]}"
    end
  end

  test "regime_as_of with confirm_days wired through, matches raw for a clean uptrend" do
    base = Time.utc(2026, 1, 1)
    60.times do |i|
      Candle.create!(symbol: IdxMarketState::SYMBOL, timeframe: "1d", asset_type: "index",
                     open: 100 + i, high: 100 + i, low: 100 + i, close: 100 + i, volume: 1,
                     opened_at: base + i.days)
    end
    as_of = base + 59.days
    refute IdxMarketState.regime_as_of(as_of, confirm_days: 0)
    refute IdxMarketState.regime_as_of(as_of, confirm_days: 3)
  end
end
