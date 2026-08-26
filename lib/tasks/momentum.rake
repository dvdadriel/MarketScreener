namespace :momentum do
  UNIVERSES = {
    "lq45"     => -> { IdxMarket::WATCHLIST },
    "extended" => -> { IdxMarket::EXTENDED_WATCHLIST },
    "all"      => -> { IdxUniverseService.all }
  }.freeze

  desc "Peringkat momentum HARI INI (top-N) + status regime. Contoh: bin/rails 'momentum:rank[extended]'"
  task :rank, [ :universe, :top_n ] => :environment do |_t, args|
    syms  = (UNIVERSES[args[:universe]] || UNIVERSES["lq45"]).call
    top_n = (args[:top_n] || 10).to_i

    blocked = IdxMarketState.long_blocked?
    puts "Regime IHSG: #{blocked ? 'RISK-OFF → CASH (tak ada posisi)' : 'RISK-ON'} (#{IdxMarketState.reason})"
    picks = MomentumRankingService.new(symbols: syms, top_n: top_n).call
    if picks.empty?
      puts "(tidak ada pick — regime risk-off atau data kurang)"
    else
      puts "Top #{picks.size} momentum (dari #{syms.size} simbol):"
      picks.each_with_index { |p, i| printf("%2d. %-10s mom=%+.1f%%  Rp %d\n", i + 1, p[:symbol].sub('.JK', ''), p[:momentum] * 100, p[:last_close]) }
    end
  end

  desc "Status forward tracking: equity paper vs IHSG sejak inception"
  task paper: :environment do
    r = MomentumPaperTracker.new.call
    if r[:tracked_days].zero?
      puts "Belum ada snapshot. Job harian momentum_snapshot mengisi otomatis (17:00 WIB), atau paksa: MomentumSnapshotJob.perform_now"
    else
      puts "Forward tracking: #{r[:inception]} → #{r[:as_of]} (#{r[:tracked_days]} hari-snapshot)"
      printf("Equity paper: %.2f (%+.2f%%)  maxDD: -%.2f%%  |  IHSG: %s%%\n",
        r[:equity], r[:total_return], r[:max_drawdown], r[:ihsg_return] || "-")
      alpha = r[:ihsg_return] ? (r[:total_return] - r[:ihsg_return]).round(2) : nil
      puts "Alpha vs IHSG: #{alpha ? format('%+.2f%%', alpha) : '-'}  |  Regime hari ini: #{r[:regime_today] || '-'}"
      puts "Holdings: #{r[:holdings].any? ? r[:holdings].map { |s| s.sub('.JK', '') }.join(', ') : 'CASH'}"
    end
  end

  desc "Walk-forward backtest momentum. buffer = tahan holding sampai keluar top-buffer (0=mati). Contoh: bin/rails 'momentum:backtest[365,extended,0,15]'"
  task :backtest, [ :days, :universe, :offset, :buffer ] => :environment do |_t, args|
    days   = (args[:days] || 365).to_i
    offset = (args[:offset] || 0).to_i
    buffer = args[:buffer].to_i
    syms   = (UNIVERSES[args[:universe]] || UNIVERSES["lq45"]).call

    puts "Momentum backtest: #{syms.size} simbol · #{days}d · offset #{offset}d · rebalance bulanan · fee 0.4% · buffer #{buffer.positive? ? buffer : 'off'}"
    r = MomentumBacktestService.new(symbols: syms, days: days, offset_days: offset, top_n: 10, cost_pct: 0.4, buffer_n: buffer).call
    printf("ret=%+.2f%%  maxDD=-%.2f%%  Sharpe=%s  win=%.0f%%  periode=%d  cash=%d\n",
      r[:total_return], r[:max_drawdown], r[:sharpe] || "-", r[:win_rate], r[:periods], r[:cash_periods])
  end

  desc "Bandingkan buffer zone (0/12/15/20) di beberapa window. Contoh: bin/rails 'momentum:buffer_sweep[extended]'"
  task :buffer_sweep, [ :universe ] => :environment do |_t, args|
    syms = (UNIVERSES[args[:universe]] || UNIVERSES["extended"]).call
    puts "Buffer sweep · #{syms.size} simbol · top-10 · fee 0.4%\n\n"
    printf("%-7s %-7s %9s %9s %8s %8s\n", "window", "buffer", "ret", "alpha", "maxDD", "Sharpe")
    [ 365, 730, 1095 ].each do |days|
      [ 0, 12, 15, 20 ].each do |buf|
        r = MomentumBacktestService.new(symbols: syms, days: days, offset_days: 0, top_n: 10,
                                        cost_pct: 0.4, buffer_n: buf).call
        printf("%-7s %-7s %+8.2f%% %+8.2f%% %7.2f%% %8s\n", "#{days}d", buf.zero? ? "off" : buf,
               r[:total_return], r[:alpha] || 0.0, r[:max_drawdown], r[:sharpe] || "-")
      end
      puts
    end
  end
end
