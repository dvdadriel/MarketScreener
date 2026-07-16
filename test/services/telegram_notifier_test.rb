require "test_helper"

class TelegramNotifierTest < ActiveSupport::TestCase
  # Parsing is the core of multi-recipient broadcast. Test it directly so the
  # result doesn't depend on whatever credentials/env happen to be configured.
  def normalize(value)
    TelegramNotifier.allocate.send(:normalize_chat_ids, value)
  end

  test "parses a comma/space separated list" do
    assert_equal %w[111 222 333], normalize("111, 222 333")
  end

  test "supports a single id" do
    assert_equal %w[999], normalize("999")
  end

  test "accepts an array" do
    assert_equal %w[111 222], normalize(%w[111 222])
  end

  test "deduplicates and ignores blanks" do
    assert_equal %w[111 222], normalize("111,,111, 222,")
  end

  test "returns empty for nil or blank" do
    assert_empty normalize(nil)
    assert_empty normalize("")
  end

  test "formats ai recommendation with label, reason and levels" do
    n = TelegramNotifier.allocate
    n.instance_variable_set(:@asset_type, "crypto")
    s = TradingSignal.new(
      symbol: "BTCUSDT", asset_type: "crypto", score: 0.82,
      fired_at: Time.utc(2026, 7, 13, 10, 0),
      metadata: {
        "entry_price" => 100.0, "sl_price" => 95.0, "tp_price" => 110.0,
        "sl_pct" => -5.0, "tp_pct" => 10.0, "risk_reward" => 2.0
      }
    )
    msg = n.send(:format_ai_recommendation, s, "Squeeze Breakout", "momentum kuat & volume naik")

    assert_includes msg, "🤖 *Rekomendasi AI* — BTCUSDT"
    assert_includes msg, "*Squeeze Breakout*"
    assert_includes msg, "_karena momentum kuat & volume naik_"
    assert_includes msg, "Score: *82%*"
    assert_includes msg, "Entry: `$100.0`"
    assert_includes msg, "R:R    `1:2.0`"
  end
end
