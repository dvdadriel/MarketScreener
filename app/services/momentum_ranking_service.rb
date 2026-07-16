# Cross-sectional momentum: peringkat universe by return trailing "6-1"
# (6 bulan, skip 1 bulan terakhir untuk hindari reversal jangka pendek), ambil top-N.
# Overlay: gate regime IHSG (cash saat risk-off) + filter likuiditas.
#
# Pergeseran filosofi dari confluence/squeeze/swing (yang men-timing entry pakai
# indikator & terbukti tak ada edge): di sini kita me-RANKING kekuatan relatif dan
# membiarkan pemenang berlanjut. Anomali momentum = paling terdokumentasi & robust.
class MomentumRankingService
  LOOKBACK      = 126   # ~6 bulan bursa
  SKIP          = 21    # ~1 bulan (lewati agar tak kena reversal jangka pendek)
  TOP_N         = 10
  MIN_LIQUIDITY = IdxScannerService::MIN_LIQUIDITY   # Rp 1M avg turnover
  # Filter anti-gorengan (tervalidasi backtest: DD turun ~2/3, Sharpe naik, alpha membaik):
  MAX_MOMENTUM  = 1.0   # buang pump parabolik >100%/6bln (return rapuh, rawan crash)
  MIN_PRICE     = 100   # buang saham receh < Rp 100 (rawan manipulasi)
  # Feasibility posisi: satu posisi (portofolio/top_n) tak boleh > 5% turnover harian —
  # lebih dari itu, entry/exit ritel akan menggerakkan harga (slippage tak terkendali).
  PORTFOLIO_IDR      = ENV.fetch("PORTFOLIO_IDR", 100_000_000).to_f   # nilai portofolio acuan
  MAX_TURNOVER_SHARE = 0.05

  # Filter kualitas (tervalidasi backtest sebelum jadi default):
  #   max_momentum:  buang pump parabolik (>100%/6bln = pump, bukan momentum)
  #   min_price:     buang saham receh (< Rp 100) yang rawan manipulasi
  #   max_extension: anti-chase — tunda entry kalau close terlalu jauh di atas MA20
  #                  (mis. 0.15 = >15% di atas MA20 = overextended, rawan pullback).
  #                  Default OFF sampai backtest membuktikan membaik (plan #5).
  def initialize(as_of: nil, symbols: nil, lookback: LOOKBACK, skip: SKIP, top_n: TOP_N,
                 max_momentum: MAX_MOMENTUM, min_price: MIN_PRICE, max_extension: nil,
                 portfolio_idr: PORTFOLIO_IDR)
    @as_of         = as_of
    @symbols       = symbols
    @lookback      = lookback
    @skip          = skip
    @top_n         = top_n
    @max_momentum  = max_momentum
    @min_price     = min_price
    @max_extension = max_extension
    @portfolio_idr = portfolio_idr.to_f
  end

  def universe
    @symbols || IdxUniverseService.all
  end

  # Returns [{symbol:, momentum:, last_close:}, ...] top-N by momentum, atau []
  # kalau regime risk-off (portofolio ke cash).
  def call
    return [] if IdxMarketState.long_blocked?

    universe.filter_map { |sym| score(sym) }
            .sort_by { |r| -r[:momentum] }
            .first(@top_n)
  end

  private

  def score(symbol)
    scope = Candle.for_asset("stock").for_symbol(symbol).for_timeframe("1d")
    scope = scope.where("opened_at <= ?", @as_of) if @as_of
    candles = scope.ordered.last(@lookback + @skip + 5)
    return nil if candles.length < @lookback + @skip + 1

    closes  = candles.map { |c| c.close.to_f }
    last    = closes.last
    return nil if last.zero?
    return nil if @min_price && last < @min_price   # buang saham receh

    # Likuiditas: avg turnover 20 hari (avg volume × harga).
    avg_vol  = candles.last(20).sum { |c| c.volume.to_f } / 20.0
    turnover = avg_vol * last
    return nil if turnover < MIN_LIQUIDITY

    # Feasibility: ukuran posisi harus muat di turnover harian (eksekusi realistis).
    if @portfolio_idr.positive?
      position = @portfolio_idr / @top_n
      return nil if position > turnover * MAX_TURNOVER_SHARE
    end

    recent = closes[-(@skip + 1)]                 # harga ~1 bulan lalu
    past   = closes[-(@skip + @lookback + 1)]      # harga ~7 bulan lalu
    return nil if past.nil? || past.zero?

    mom = recent / past - 1.0
    return nil if @max_momentum && mom > @max_momentum   # buang pump parabolik

    # Anti-chase: overextended di atas MA20 → rawan pullback tajam, tunda entry.
    if @max_extension
      ma20 = closes.last(20).sum / 20.0
      return nil if ma20.positive? && last > ma20 * (1 + @max_extension)
    end

    { symbol: symbol, momentum: mom.round(4), last_close: last }
  end
end
