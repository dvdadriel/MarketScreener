require "test_helper"

class AlertDispatcherJobTest < ActiveSupport::TestCase
  # Replace an instance method on `klass` with `impl` for the block, then restore.
  # Works for private methods too (define_method ignores visibility).
  def stub_method(klass, name, impl)
    klass.class_eval do
      alias_method :"__orig_#{name}", name
      define_method(name) { |*a, **k| impl.call(*a, **k) }
    end
    yield
  ensure
    klass.class_eval do
      alias_method name, :"__orig_#{name}"
      remove_method :"__orig_#{name}"
    end
  end

  # asset_type stock: crypto dispatch di-gate off (CRYPTO_ENABLED=false); path AI-rank sama.
  def buy_signal(symbol, type: "BUY")
    TradingSignal.create!(
      symbol: symbol, strategy: "SQUEEZE_BREAKOUT", signal_type: type,
      score: 0.85, asset_type: "stock", alerted: false, fired_at: Time.current,
      metadata: { "entry_price" => 100.0, "sl_price" => 95.0, "tp_price" => 110.0, "timeframe" => "1d" }
    )
  end

  test "ok status sends ai recommendations and marks all alerted" do
    s = buy_signal("BBCA.JK")
    sent = []
    stub_method(AlertDispatcherJob, :broadcast_signal, ->(*) {}) do
    stub_method(TradingViewClient, :rating, ->(**) { {} }) do
    stub_method(AiRecommenderService, :call, ->(*) { { status: :ok, picks: [ { signal: s, reason: "kuat" } ] } }) do
    stub_method(TelegramNotifier, :send_ai_recommendation, ->(sig, label, reason) { sent << [ sig.symbol, label, reason ] }) do
      AlertDispatcherJob.new.perform
    end end end end

    assert_equal [ [ "BBCA.JK", "Squeeze Breakout", "kuat" ] ], sent
    assert s.reload.alerted?
  end

  test "unavailable status falls back to raw send_signal" do
    s = buy_signal("TLKM.JK")
    sent = []
    stub_method(AlertDispatcherJob, :broadcast_signal, ->(*) {}) do
    stub_method(TradingViewClient, :rating, ->(**) { nil }) do
    stub_method(AiRecommenderService, :call, ->(*) { { status: :unavailable, picks: [] } }) do
    stub_method(TelegramNotifier, :send_signal, ->(sig) { sent << sig.symbol }) do
      AlertDispatcherJob.new.perform
    end end end end

    assert_equal [ "TLKM.JK" ], sent
    assert s.reload.alerted?
  end

  test "none status sends nothing but still marks alerted" do
    s = buy_signal("ASII.JK")
    ai_sent = []
    raw_sent = []
    stub_method(AlertDispatcherJob, :broadcast_signal, ->(*) {}) do
    stub_method(TradingViewClient, :rating, ->(**) { {} }) do
    stub_method(AiRecommenderService, :call, ->(*) { { status: :none, picks: [] } }) do
    stub_method(TelegramNotifier, :send_ai_recommendation, ->(*) { ai_sent << 1 }) do
    stub_method(TelegramNotifier, :send_signal, ->(*) { raw_sent << 1 }) do
      AlertDispatcherJob.new.perform
    end end end end end

    assert_empty ai_sent
    assert_empty raw_sent
    assert s.reload.alerted?
  end
end
