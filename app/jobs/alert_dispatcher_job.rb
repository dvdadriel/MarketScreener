class AlertDispatcherJob < ApplicationJob
  queue_as :realtime

  # BUY signals go through the AI ranker; only its endorsed picks reach Telegram.
  # SELL signals are still created & paper-traded but never alerted (can't short IDX,
  # most users are spot-only). If the AI is unavailable we fall back to raw BUY alerts.
  def perform
    TradingSignal.unalerted.high_score.group_by(&:asset_type).each do |asset_type, signals|
      buys = signals.select { |s| s.signal_type == "BUY" }
      # CONFLUENCE dibungkam: backtest tunjukkan tak ada edge (rugi OOS). Tetap di-finalize
      # → paper-trade diam sebagai baseline, tapi jangan kirim alert Telegram.
      # Crypto juga dimatikan (kecuali CRYPTO_ENABLED).
      alertable = buys.reject { |s| s.strategy.to_s.start_with?("CONFLUENCE") }
      alertable = [] if TelegramCommandService.alerts_muted?   # /mute via bot; sinyal tetap di-finalize
      send_recommendations(asset_type, alertable) if alertable.any? && (asset_type != "crypto" || CRYPTO_ENABLED)
      signals.each { |s| finalize(s) } # includes SELL & confluence, so they don't linger unalerted
    end
  end

  private

  def send_recommendations(asset_type, buys)
    notifier = TelegramNotifier.new(asset_type: asset_type)
    tv       = TradingViewClient.new.rating(symbols: buys.map(&:symbol), asset_type: asset_type) || {}
    result   = AiRecommenderService.new(buys, tv_ratings: tv).call

    case result[:status]
    when :ok
      result[:picks].each do |pick|
        signal = pick[:signal]
        notifier.send_ai_recommendation(signal, SetupLabeler.label(signal), pick[:reason])
      end
    when :unavailable
      buys.each { |s| notifier.send_signal(s) } # degrade to prior behavior
    end
    # :none => intentional silence
  rescue => e
    Rails.logger.error("[AlertDispatcherJob] #{asset_type} dispatch: #{e.class}: #{e.message}")
  end

  def finalize(signal)
    signal.update!(alerted: true)
    broadcast_signal(signal)
  rescue => e
    Rails.logger.error("[AlertDispatcherJob] signal #{signal.id}: #{e.message}")
  end

  def broadcast_signal(signal)
    target = signal.asset_type == "stock" ? "stock_signals_body" : "crypto_signals_body"

    Turbo::StreamsChannel.broadcast_prepend_to(
      "dashboard",
      target:  target,
      partial: "dashboard/signal_row",
      locals:  { signal: signal }
    )
  end
end
