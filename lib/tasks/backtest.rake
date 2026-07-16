namespace :backtest do
  # Args: days, strategy, universe, cost, slippage, risk
  #   universe: lq45 (default) | extended (~KOMPAS100) | all (full IDX universe)
  #   cost:     biaya round-trip % (default 0.4, khas IDX)
  #   slippage: adverse per-leg % (default 0.1)
  #   risk:     risiko per-trade % ekuitas untuk position sizing (default 1.0; 0 = matikan)
  desc "Validasi strategi di candle historis. Contoh: bin/rails 'backtest:run[365,all,extended,0.4,0.1,1.0]'"
  task :run, [ :days, :strategy, :universe, :cost, :slippage, :risk ] => :environment do |_t, args|
    days       = (args[:days] || 365).to_i
    cost       = (args[:cost] || 0.4).to_f
    slippage   = (args[:slippage] || 0.1).to_f
    risk       = (args[:risk] || 1.0).to_f
    strategies = if args[:strategy].present? && args[:strategy] != "all"
      [ args[:strategy] ]
    else
      BacktestService::STRATEGIES.keys
    end
    symbols = case args[:universe].to_s
    when "extended" then IdxMarket::EXTENDED_WATCHLIST
    when "all"      then IdxUniverseService.all
    else                 IdxMarket::WATCHLIST   # lq45 default
    end

    puts "Backtest: #{symbols.size} simbol · #{days} hari · #{strategies.join(', ')} · fee #{cost}% · slip #{slippage}%/leg · risk #{risk}%/trade"
    puts "Fetch histori + simulasi (bisa beberapa menit)...\n\n"

    report = BacktestService.new(
      symbols: symbols, asset_type: "stock", days: days, strategies: strategies,
      cost_pct: cost, slippage_pct: slippage, risk_pct: risk
    ).call

    puts "=== BACKTEST REPORT (#{report[:symbols]} simbol · #{report[:days]}d · #{report[:total_trades]} trade · risk #{report[:risk_pct]}%/trade) ==="
    printf("%-14s %6s %7s %9s %6s %8s %9s %8s\n", "STRATEGY", "n", "WR%", "exp%", "PF", "Sharpe", "ret%", "maxDD%")
    puts "(tidak ada trade — cek ketersediaan candle historis)" if report[:per_strategy].empty?
    report[:per_strategy].each do |s|
      printf("%-14s %6d %7.1f %+9.2f %6s %8s %9s %8s\n",
        s[:strategy], s[:trades], s[:win_rate], s[:expectancy],
        s[:profit_factor] || "-", s[:sharpe] || "-",
        s[:total_return] ? format("%+.1f", s[:total_return]) : "-",
        s[:max_dd_real] ? "-#{s[:max_dd_real]}" : "-")
    end
    puts "\nCatatan: fee #{cost}% + slippage #{slippage}%/leg + sizing risk #{risk}%/trade. ret%/maxDD% = akun ber-compound nyata."
    puts "Gate regime di-bypass. Lihat guideline/list_improvement.md."
  end
end
