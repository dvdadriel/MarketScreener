require "test_helper"

# Fokus: logika buffer zone (tahan holding sampai keluar top-buffer) dan guard
# kelengkapan data. Ranking di-stub supaya yang diuji murni aturan seleksinya,
# bukan data candle.
class MomentumBacktestServiceTest < ActiveSupport::TestCase
  # Meniru MomentumRankingService: kembalikan hanya top_n nama teratas.
  # Kwarg yang diterima direkam supaya invariant portfolio_idr bisa diuji —
  # sebelumnya semua kwarg selain top_n dibuang, sehingga rescaling yang
  # justru paling halus di rank_at tidak teruji sama sekali.
  class FakeRank
    class << self
      attr_accessor :last_kwargs
    end

    def initialize(order, kwargs)
      @order  = order
      @top_n  = kwargs[:top_n]
      self.class.last_kwargs = kwargs
    end

    def call = @order.first(@top_n).map { |s| { symbol: s } }
  end

  ORDER = %w[A B C D E F].freeze   # peringkat 1..6

  def rank_at(holdings, buffer_n: 0, top_n: 3)
    FakeRank.last_kwargs = nil
    svc  = MomentumBacktestService.new(symbols: ORDER, top_n: top_n, buffer_n: buffer_n)
    orig = MomentumRankingService.method(:new)
    MomentumRankingService.define_singleton_method(:new) { |**kw| FakeRank.new(ORDER, kw) }
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

  # Invariant yang paling halus di rank_at, dan yang paling mudah rusak tanpa
  # terdeteksi: meminta n nama sementara ukuran posisi tetap 1/top_n berarti
  # portfolio_idr harus diskalakan n/top_n. Kalau tidak, buffer diam-diam
  # melonggarkan filter feasibility dan hasil antar-konfigurasi tak sebanding.
  test "buffer: portfolio_idr diskalakan n/top_n supaya filter feasibility identik" do
    rank_at(%w[D], buffer_n: 5, top_n: 3)

    kw = FakeRank.last_kwargs
    assert_equal 5, kw[:top_n], "harus meminta buffer_n nama, bukan top_n"
    assert_in_delta MomentumRankingService::PORTFOLIO_IDR * 5 / 3.0,
                    kw[:portfolio_idr], 1.0,
                    "portfolio_idr harus diskalakan 5/3 saat buffer_n=5 dan top_n=3"
  end

  test "tanpa buffer: portfolio_idr tetap utuh" do
    rank_at(%w[D], buffer_n: 0, top_n: 3)

    kw = FakeRank.last_kwargs
    assert_equal 3, kw[:top_n]
    assert_in_delta MomentumRankingService::PORTFOLIO_IDR.to_f,
                    kw[:portfolio_idr], 1.0,
                    "tanpa buffer, n == top_n, jadi skalanya 1.0"
  end

  # === check_coverage! ===
  #
  # Guard ini menjaga agar backtest tidak menghasilkan angka dari universe
  # pincang. Sebelumnya tidak punya test sama sekali — padahal ia hard raise
  # pada jalur yang menentukan setiap angka yang dipublikasikan: false positive
  # memblokir seluruh sweep, false negative mengembalikan bug yang justru
  # dibuat untuk dicegah.

  def coverage_svc(top_n: 10)
    MomentumBacktestService.new(symbols: %w[A], top_n: top_n)
  end

  # need = lookback + skip + 1
  def need_for(svc)
    svc.instance_variable_get(:@lookback) + svc.instance_variable_get(:@skip) + 1
  end

  def prices_with(svc, total:, missing:)
    need = need_for(svc)
    (1..total).to_h do |i|
      candles = i <= missing ? Array.new(need - 1, :c) : Array.new(need, :c)
      [ "S#{i}", candles ]
    end
  end

  test "check_coverage!: prices kosong lolos tanpa raise" do
    svc = coverage_svc
    assert_nothing_raised { svc.send(:check_coverage!, {}) }
  end

  test "check_coverage!: tepat di batas 10% masih lolos" do
    svc = coverage_svc
    # 1 dari 10 = 0.10, dan guardnya `share <= MAX_MISSING_SHARE`
    assert_nothing_raised { svc.send(:check_coverage!, prices_with(svc, total: 10, missing: 1)) }
  end

  test "check_coverage!: di atas 10% raise dan menyebut angkanya" do
    svc = coverage_svc
    err = assert_raises(RuntimeError) do
      svc.send(:check_coverage!, prices_with(svc, total: 10, missing: 2))
    end
    assert_match(/Data tak lengkap/, err.message)
    assert_match(/2\/10/, err.message)
    assert_match(/20\.0%/, err.message)
  end

  test "check_coverage!: nil dihitung sebagai simbol yang kurang datanya" do
    svc  = coverage_svc
    need = need_for(svc)
    prices = { "A" => nil, "B" => nil, "C" => Array.new(need, :c) }

    err = assert_raises(RuntimeError) { svc.send(:check_coverage!, prices) }
    assert_match(/2\/3/, err.message)
  end

  test "check_coverage!: universe lengkap tidak pernah raise" do
    svc = coverage_svc
    assert_nothing_raised { svc.send(:check_coverage!, prices_with(svc, total: 50, missing: 0)) }
  end

  # MAX_MISSING_SHARE = 0.10 terbukti TERLALU LONGGAR di lapangan: pada
  # 2026-08-26, backtest 365d/buffer-15 memberi -6,78% dengan cache candle
  # dingin lalu +1,44% setelah hangat — selisih 8,2 poin persentase — dan guard
  # ini tidak menyala. Test ini memaku nilai ambangnya supaya perubahannya
  # menjadi keputusan yang disengaja, bukan pergeseran diam-diam.
  test "MAX_MISSING_SHARE terpaku pada 0.10" do
    assert_in_delta 0.10, MomentumBacktestService::MAX_MISSING_SHARE, 1e-9
  end
end
