require "test_helper"

# Fokus: logika buffer zone (tahan holding sampai keluar top-buffer). Ranking di-stub
# supaya yang diuji murni aturan seleksinya, bukan data candle.
class MomentumBacktestServiceTest < ActiveSupport::TestCase
  # Meniru MomentumRankingService: kembalikan hanya top_n nama teratas.
  class FakeRank
    def initialize(order, top_n) = (@order = order; @top_n = top_n)
    def call = @order.first(@top_n).map { |s| { symbol: s } }
  end

  ORDER = %w[A B C D E F].freeze   # peringkat 1..6

  def rank_at(holdings, buffer_n: 0)
    svc  = MomentumBacktestService.new(symbols: ORDER, top_n: 3, buffer_n: buffer_n)
    orig = MomentumRankingService.method(:new)
    MomentumRankingService.define_singleton_method(:new) { |**kw| FakeRank.new(ORDER, kw[:top_n]) }
    svc.send(:rank_at, Time.utc(2026, 1, 1), holdings)
  ensure
    MomentumRankingService.define_singleton_method(:new, orig)
  end

  test "tanpa buffer: selalu top-N murni" do
    assert_equal %w[A B C], rank_at(%w[D], buffer_n: 0)
  end

  test "buffer: holding yang masih di dalam buffer ditahan, sisanya diisi top-N" do
    kept = rank_at(%w[D], buffer_n: 5)          # D peringkat 4, masih di top-5
    assert_includes kept, "D"
    assert_equal 3, kept.size
    assert_equal %w[A B D], kept.sort
  end

  test "buffer: holding yang jatuh keluar buffer dilepas" do
    assert_equal %w[A B C], rank_at(%w[F], buffer_n: 5)   # F peringkat 6 > buffer
  end

  test "buffer <= top_n dianggap mati" do
    assert_equal %w[A B C], rank_at(%w[D], buffer_n: 3)
  end
end
