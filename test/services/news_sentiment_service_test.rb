require "test_helper"

class NewsSentimentServiceTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(titles) = @titles = titles
    def headlines(**) = @titles
  end

  class FakeClient
    def initialize(result) = @result = result
    def chat(**) = @result
  end

  def build(client:, fetcher:)
    NewsSentimentService.new(client: client, fetcher: fetcher)
  end

  test "returns structured sentiment" do
    svc = build(
      client:  FakeClient.new({ "score" => 0.8, "label" => "bullish", "reason" => "naik" }),
      fetcher: FakeFetcher.new([ "Coin melonjak", "Adopsi meningkat" ])
    )
    out = svc.score(symbol: "BTCUSDT", asset_type: "crypto")
    assert_equal 0.8, out["score"]
    assert_equal "bullish", out["label"]
    assert_equal 2, out["headlines_count"]
  end

  test "returns nil when no headlines" do
    svc = build(client: FakeClient.new(nil), fetcher: FakeFetcher.new([]))
    assert_nil svc.score(symbol: "BTCUSDT", asset_type: "crypto")
  end

  test "returns nil when llm output malformed" do
    svc = build(client: FakeClient.new({ "nonsense" => true }), fetcher: FakeFetcher.new([ "judul" ]))
    assert_nil svc.score(symbol: "BTCUSDT", asset_type: "crypto")
  end

  test "clamps score into -1..1" do
    svc = build(
      client:  FakeClient.new({ "score" => 5, "label" => "bullish", "reason" => "x" }),
      fetcher: FakeFetcher.new([ "judul" ])
    )
    assert_equal 1.0, svc.score(symbol: "BTCUSDT", asset_type: "crypto")["score"]
  end
end
