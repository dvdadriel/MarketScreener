class SignalEvaluatorJob < ApplicationJob
  queue_as :realtime

  def perform(asset_type: "crypto")
    watchlist = watchlist_for(asset_type)
    new_signals = []

    watchlist.each do |symbol|
      new_signals.concat(evaluate_symbol(symbol, asset_type))
    rescue => e
      Rails.logger.error("[SignalEvaluatorJob] #{symbol}: #{e.message}")
    end

    Rails.logger.info("[SignalEvaluatorJob #{asset_type}] generated #{new_signals.size} signals from #{watchlist.size} symbols")

    AlertDispatcherJob.perform_later if new_signals.any?
  end

  private

  # Confluence + squeeze-breakout jalan berdampingan; masing-masing cooldown sendiri.
  def evaluate_symbol(symbol, asset_type)
    signals = []

    unless SignalConfluenceService.cooldown?(symbol)
      if (r = SignalConfluenceService.new(symbol: symbol, asset_type: asset_type).evaluate)
        signals << TradingSignal.create!(r)
      end
    end

    # Squeeze dimatikan untuk saham: backtest tunjukkan net-rugi di semua potongan
    # (LQ45 & universe penuh, gross & fee). Masih dipakai crypto.
    if asset_type != "stock" && !SqueezeBreakoutService.cooldown?(symbol)
      if (r = SqueezeBreakoutService.new(symbol: symbol, asset_type: asset_type).evaluate)
        signals << TradingSignal.create!(r)
      end
    end

    signals.each { |s| annotate_sentiment(s) }
    signals
  end

  # News-sentiment annotation (optional). Never blocks signal creation.
  def annotate_sentiment(signal)
    s = NewsSentimentService.new.score(symbol: signal.symbol, asset_type: signal.asset_type)
    return unless s

    signal.update!(metadata: (signal.metadata || {}).merge("news_sentiment" => s))
  rescue => e
    Rails.logger.warn("[SignalEvaluatorJob] sentiment #{signal.symbol}: #{e.message}")
  end

  def watchlist_for(asset_type)
    case asset_type
    when "stock"
      IdxUniverseService.all
    else
      MarketScannerService.watchlist
    end
  end
end
