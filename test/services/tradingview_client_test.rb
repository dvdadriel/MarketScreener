require "test_helper"
require "ostruct"

class TradingViewClientTest < ActiveSupport::TestCase
  # Override Http.post_json with `impl` for the block, then restore.
  def stub_post_json(impl)
    singleton = Http.singleton_class
    orig = Http.method(:post_json)
    singleton.define_method(:post_json) { |*a, **k| impl.call(*a, **k) }
    yield
  ensure
    singleton.define_method(:post_json) { |*a, **k| orig.call(*a, **k) }
  end

  def resp(data)
    OpenStruct.new(body: { data: data }.to_json)
  end

  # columns order: Recommend.All, Recommend.MA, RSI, close, change, volume
  test "maps crypto ticker and returns rating" do
    sent = nil
    impl = ->(url, payload, **) do
      sent = { url: url, payload: payload }
      resp([ { "s" => "BINANCE:BTCUSDT", "d" => [ 0.6, 0.5, 55.0, 100.0, 2.5, 999 ] } ])
    end
    stub_post_json(impl) do
      out = TradingViewClient.new.rating(symbols: [ "BTCUSDT" ], asset_type: "crypto")
      assert_equal "STRONG_BUY", out["BTCUSDT"][:recommend]
      assert_equal 55.0, out["BTCUSDT"][:rsi]
      assert_equal 2.5,  out["BTCUSDT"][:change]
    end
    assert_match %r{/crypto/scan\z}, sent[:url]
    assert_equal [ "BINANCE:BTCUSDT" ], sent[:payload][:symbols][:tickers]
  end

  test "maps IDX ticker on indonesia scanner" do
    impl = ->(url, payload, **) do
      assert_match %r{/indonesia/scan\z}, url
      assert_equal [ "IDX:BBCA" ], payload[:symbols][:tickers]
      resp([])
    end
    stub_post_json(impl) do
      TradingViewClient.new.rating(symbols: [ "BBCA.JK" ], asset_type: "stock")
    end
  end

  test "recommend label thresholds" do
    tv = TradingViewClient.new
    assert_equal "STRONG_BUY",  tv.send(:recommend_label, 0.5)
    assert_equal "BUY",         tv.send(:recommend_label, 0.1)
    assert_equal "NEUTRAL",     tv.send(:recommend_label, 0.0)
    assert_equal "SELL",        tv.send(:recommend_label, -0.2)
    assert_equal "STRONG_SELL", tv.send(:recommend_label, -0.6)
    assert_equal "NEUTRAL",     tv.send(:recommend_label, nil)
  end

  test "returns nil on http error" do
    stub_post_json(->(*a, **k) { raise Http::RetryableError.new("boom") }) do
      assert_nil TradingViewClient.new.rating(symbols: [ "BTCUSDT" ], asset_type: "crypto")
    end
  end

  test "returns empty hash for empty symbols without calling http" do
    stub_post_json(->(*a, **k) { flunk("should not be called") }) do
      assert_equal({}, TradingViewClient.new.rating(symbols: [], asset_type: "crypto"))
    end
  end
end
