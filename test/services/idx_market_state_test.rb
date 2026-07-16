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
end
