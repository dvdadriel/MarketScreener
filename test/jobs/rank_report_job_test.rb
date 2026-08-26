require "test_helper"

class RankReportJobTest < ActiveSupport::TestCase
  class FakeNotifier
    attr_reader :texts, :signals
    def initialize = (@texts = []; @signals = [])
    def send_text(t) = @texts << t
    def send_signal(s) = @signals << s
  end

  class FakeRank
    def initialize(picks) = @picks = picks
    def call = @picks
  end

  def pick(sym) = { symbol: sym, momentum: 0.5, last_close: 1000.0 }

  def run_job(picks, notifier)
    origs = { IdxMarketState => IdxMarketState.method(:long_blocked?),
              MomentumRankingService => MomentumRankingService.method(:new),
              TelegramNotifier => TelegramNotifier.method(:new) }
    IdxMarketState.define_singleton_method(:long_blocked?) { false }
    MomentumRankingService.define_singleton_method(:new) { |**| FakeRank.new(picks) }
    TelegramNotifier.define_singleton_method(:new) { |**| notifier }
    RankReportJob.new.perform("extended")
  ensure
    origs.each { |k, m| k.define_singleton_method(m.name, m) }
  end

  # Env test pakai null_store — pasang memory store supaya deteksi "berubah/tidak" teruji.
  setup do
    @orig_cache = Rails.method(:cache)
    store = ActiveSupport::Cache::MemoryStore.new
    Rails.define_singleton_method(:cache) { store }
  end

  teardown { Rails.define_singleton_method(:cache, @orig_cache) }

  test "kirim daftar + kartu untuk setiap pick pada run pertama" do
    n = FakeNotifier.new
    run_job([ pick("AAA.JK"), pick("BBB.JK") ], n)

    assert_equal 1, n.texts.size
    assert_equal 2, n.signals.size
    assert_equal %w[BUY BUY], n.signals.map(&:signal_type)
  end

  test "diam kalau komposisi top-10 tidak berubah" do
    picks = [ pick("AAA.JK") ]
    run_job(picks, FakeNotifier.new)

    n = FakeNotifier.new
    run_job(picks, n)
    assert_empty n.texts
    assert_empty n.signals
  end

  test "hanya pick baru yang dapat kartu BUY" do
    run_job([ pick("AAA.JK") ], FakeNotifier.new)

    n = FakeNotifier.new
    run_job([ pick("AAA.JK"), pick("CCC.JK") ], n)
    assert_equal 1, n.texts.size
    assert_equal [ "CCC.JK" ], n.signals.map(&:symbol)
  end
end
