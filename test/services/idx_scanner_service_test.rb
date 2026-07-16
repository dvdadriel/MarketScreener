require "test_helper"
require "ostruct"

class IdxScannerServiceTest < ActiveSupport::TestCase
  def svc = IdxScannerService.new

  test "score_rs rewards outperformance over IHSG" do
    assert_equal 100, svc.send(:score_rs, 0.15)   # +15% vs index
    assert_equal 70,  svc.send(:score_rs, 0.02)   # +2%
    assert_equal 10,  svc.send(:score_rs, -0.20)  # laggard
    assert_equal 50,  svc.send(:score_rs, nil)    # netral saat data indeks tak ada
  end

  test "relative_strength = stock return minus index return" do
    # 61 candle: harga naik 100 -> 121 (return +21%)
    closes = (0..60).map { |i| 100.0 + i * 0.35 }   # ~100 -> 121
    candles = closes.map { |c| OpenStruct.new(close: c) }
    rs = svc.send(:relative_strength, candles, 0.10)  # index +10%
    assert_in_delta 0.11, rs, 0.02                    # stock ~+21% - 10% ≈ +11%
  end

  test "relative_strength nil when index data missing" do
    candles = Array.new(61) { OpenStruct.new(close: 100.0) }
    assert_nil svc.send(:relative_strength, candles, nil)
  end
end
