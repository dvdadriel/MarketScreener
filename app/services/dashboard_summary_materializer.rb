# MomentumPaperTracker dan PaperTradeStats itu perhitungan path-dependent
# (equity curve, rebalancing, drawdown, Sharpe) — bukan agregat SQL biasa.
# Reimplementasi sebagai Postgres view berisiko salah angka, jadi hasil Ruby
# yang sudah teruji ini di-materialize apa adanya ke tabel ringkasan, supaya
# dashboard statis (React + Supabase REST) bisa baca tanpa menjalankan Ruby.
class DashboardSummaryMaterializer
  ASSET_TYPES = %w[stock].freeze

  def call
    materialize_momentum
    ASSET_TYPES.each { |t| materialize_paper_stats(t) }
  end

  private

  def materialize_momentum
    data = MomentumPaperTracker.new.call
    summary = MomentumTrackerSummary.first_or_initialize
    summary.update!(data: data.as_json)
  end

  def materialize_paper_stats(asset_type)
    data = PaperTradeStats.for(asset_type)
    summary = PaperTradeStatsSummary.find_or_initialize_by(asset_type: asset_type)
    summary.update!(data: serialize_stats(data))
  end

  def serialize_stats(data)
    data.merge(
      best_trade: trade_ref(data[:best_trade]),
      worst_trade: trade_ref(data[:worst_trade])
    ).as_json
  end

  def trade_ref(trade)
    return nil unless trade

    {
      symbol: trade.symbol,
      strategy: trade.strategy,
      pnl_pct: trade.pnl_pct&.to_f,
      exit_at: trade.exit_at
    }
  end
end
