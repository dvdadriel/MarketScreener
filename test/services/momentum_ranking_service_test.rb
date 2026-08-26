require "test_helper"

class MomentumRankingServiceTest < ActiveSupport::TestCase
  # Stub IdxMarketState.long_blocked? (hindari fetch ^JKSE live di test).
  def with_regime(blocked:)
    orig = IdxMarketState.method(:long_blocked?)
    IdxMarketState.define_singleton_method(:long_blocked?) { blocked }
    yield
  ensure
    IdxMarketState.define_singleton_method(:long_blocked?, orig)
  end

  # Buat deret candle harian; `closes` menentukan trajektori, volume seragam.
  def series(symbol, closes:, volume: 20_000_000)   # turnover > Rp 1M floor
    base = Time.utc(2026, 1, 1)
    closes.each_with_index do |px, i|
      Candle.create!(symbol: symbol, timeframe: "1d", asset_type: "stock",
                     open: px, high: px, low: px, close: px, volume: volume,
                     opened_at: base + i.days)
    end
  end

  # lookback 10 + skip 2 => butuh 13 candle. Harga cukup tinggi supaya turnover > Rp 1M.
  def opts = { lookback: 10, skip: 2, top_n: 5 }

  test "ranks higher-momentum symbol first" do
    series("STRONG.JK", closes: (1..15).map { |i| 100.0 + i * 5 })   # naik kuat
    series("FLAT.JK",   closes: Array.new(15, 100.0))                # datar
    with_regime(blocked: false) do
      ranked = MomentumRankingService.new(symbols: %w[STRONG.JK FLAT.JK], **opts).call
      assert_equal "STRONG.JK", ranked.first[:symbol]
      assert_operator ranked.first[:momentum], :>, 0
    end
  end

  test "excludes illiquid symbols (turnover below floor)" do
    series("THIN.JK", closes: (1..15).map { |i| 100.0 + i * 5 }, volume: 10) # turnover kecil
    with_regime(blocked: false) do
      ranked = MomentumRankingService.new(symbols: %w[THIN.JK], **opts).call
      assert_empty ranked
    end
  end

  test "returns empty (cash) when regime risk-off" do
    series("STRONG.JK", closes: (1..15).map { |i| 100.0 + i * 5 })
    with_regime(blocked: true) do
      assert_empty MomentumRankingService.new(symbols: %w[STRONG.JK], **opts).call
    end
  end

  test "ignore_regime still ranks during risk-off (watchlist, not a buy signal)" do
    series("STRONG.JK", closes: (1..15).map { |i| 100.0 + i * 5 })
    with_regime(blocked: true) do
      picks = MomentumRankingService.new(symbols: %w[STRONG.JK], ignore_regime: true, **opts).call
      assert_equal %w[STRONG.JK], picks.map { |p| p[:symbol] }
    end
  end

  test "excludes pump (momentum > cap) — anti-gorengan" do
    # naik >100% (pump); harga tinggi & likuid, jadi HANYA MAX_MOMENTUM yang membuang.
    series("PUMP.JK", closes: (1..15).map { |i| 100.0 + i * 40 })
    with_regime(blocked: false) do
      assert_empty MomentumRankingService.new(symbols: %w[PUMP.JK], **opts).call
    end
  end

  test "excludes penny stocks below MIN_PRICE" do
    series("PENNY.JK", closes: (1..15).map { |i| 10.0 + i }, volume: 200_000_000) # likuid tapi < Rp 100
    with_regime(blocked: false) do
      assert_empty MomentumRankingService.new(symbols: %w[PENNY.JK], **opts).call
    end
  end

  test "max_extension excludes overextended stock, off by default" do
    # Naik moderat lalu melonjak jauh di atas MA20 di bar terakhir.
    closes = (1..14).map { |i| 100.0 + i } + [ 160.0 ]
    series("EXT.JK", closes: closes)
    with_regime(blocked: false) do
      # default (off): lolos
      assert_equal 1, MomentumRankingService.new(symbols: %w[EXT.JK], **opts).call.size
      # dengan filter 15%: dibuang (160 >> MA20 × 1.15)
      assert_empty MomentumRankingService.new(symbols: %w[EXT.JK], max_extension: 0.15, **opts).call
    end
  end

  test "position feasibility: huge portfolio excludes stock whose turnover can't absorb it" do
    series("OK.JK", closes: (1..15).map { |i| 100.0 + i * 5 })   # turnover ~ Rp 3,5 M
    with_regime(blocked: false) do
      # default 100 juta: lolos
      assert_equal 1, MomentumRankingService.new(symbols: %w[OK.JK], **opts).call.size
      # portofolio 20 miliar → posisi 4 miliar >> 5% turnover → dibuang
      assert_empty MomentumRankingService.new(symbols: %w[OK.JK], portfolio_idr: 20_000_000_000, top_n: 5, lookback: 10, skip: 2).call
    end
  end

  # Residual momentum harus memilih saham yang menang KARENA dirinya sendiri, bukan
  # karena beta tinggi ke IHSG. Konstruksi: BETA.JK return 2× indeks (residual nol,
  # tapi return mentah TERBESAR), IDIO.JK return 1× indeks + 0,1%/hari (residual positif).
  # Ranking mentah → BETA menang; ranking residual → IDIO menang.
  test "residual momentum ranks idiosyncratic winner above pure-beta winner" do
    n    = 75
    base = Time.utc(2026, 1, 1)
    # Return indeks harus BERVARIASI — kalau konstan, beta menyerap seluruh drift saham
    # dan residual selalu nol (konstruksi degenerate).
    r    = ->(i) { 0.002 + 0.004 * Math.sin(i) }
    cum  = ->(i, extra) { (0...i).sum { |k| r.(k) + extra } }
    n.times do |i|
      Candle.create!(symbol: IdxMarketState::SYMBOL, timeframe: "1d", asset_type: "index",
                     open: 1000, high: 1000, low: 1000, close: 1000 * Math.exp(cum.(i, 0)),
                     volume: 0, opened_at: base + i.days)
    end
    # BETA.JK: persis 2× return indeks → alpha nol, tapi return mentah TERBESAR.
    series("BETA.JK", closes: (0...n).map { |i| 100.0 * Math.exp(2 * cum.(i, 0)) })
    # IDIO.JK: 1× indeks + 0,1%/hari milik sendiri → alpha positif.
    series("IDIO.JK", closes: (0...n).map { |i| 100.0 * Math.exp(cum.(i, 0.001)) })

    o = { lookback: 60, skip: 5, top_n: 5 }
    with_regime(blocked: false) do
      raw = MomentumRankingService.new(symbols: %w[BETA.JK IDIO.JK], **o).call
      assert_equal "BETA.JK", raw.first[:symbol], "return mentah: beta tinggi menang"

      res = MomentumRankingService.new(symbols: %w[BETA.JK IDIO.JK], residual: true, **o).call
      assert_equal "IDIO.JK", res.first[:symbol], "residual: excess return sendiri yang menang"
      assert_in_delta 0.0, res.find { |x| x[:symbol] == "BETA.JK" }[:momentum], 0.01,
                      "saham yang cuma ikut indeks → residual ~0"
    end
  end

  test "skips symbols with insufficient history" do
    series("SHORT.JK", closes: (1..5).map { |i| 100.0 + i })   # < lookback+skip
    with_regime(blocked: false) do
      assert_empty MomentumRankingService.new(symbols: %w[SHORT.JK], **opts).call
    end
  end
end
