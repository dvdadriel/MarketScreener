require "net/http"
require "json"

class TelegramNotifier
  API_BASE = "https://api.telegram.org"

  # Pass asset_type ("crypto" or "stock") to route to the right bot.
  # Falls back to the legacy single bot if the asset-specific one is missing.
  #
  # Multiple recipients: set the chat id env/credential to a comma-separated list
  # (e.g. TELEGRAM_CRYPTO_CHAT_ID="111,222,333") or use a `chat_ids:` array in
  # credentials. Every message is then broadcast to all of them.
  def initialize(asset_type: "crypto")
    creds = Rails.application.credentials.telegram || {}
    scope = creds[asset_type.to_sym] || creds

    @token = scope[:bot_token] || ENV["TELEGRAM_#{asset_type.upcase}_BOT_TOKEN"] || ENV["TELEGRAM_BOT_TOKEN"]

    raw_chat_ids = scope[:chat_ids] || scope[:chat_id] ||
                   ENV["TELEGRAM_#{asset_type.upcase}_CHAT_ID"] || ENV["TELEGRAM_CHAT_ID"]
    @chat_ids = normalize_chat_ids(raw_chat_ids)
    @asset_type = asset_type
  end

  def send_signal(signal)
    return unless configured?

    post_message(format_message(signal))
  rescue => e
    Rails.logger.error("[TelegramNotifier:#{@asset_type}] #{e.class}: #{e.message}")
  end

  def send_ai_recommendation(signal, label, reason)
    return unless configured?

    post_message(format_ai_recommendation(signal, label, reason))
  rescue => e
    Rails.logger.error("[TelegramNotifier:#{@asset_type}] #{e.class}: #{e.message}")
  end

  def send_watchlist_change(added:, removed:)
    return unless configured?
    return if added.empty? && removed.empty?

    lines = [ "📡 *Watchlist Updated*" ]
    if added.any?
      lines << ""
      lines << "🟢 *Added (#{added.size}):*"
      lines << added.first(20).map { |s| "`#{s}`" }.join(" ")
      lines << "_+ #{added.size - 20} more_" if added.size > 20
    end
    if removed.any?
      lines << ""
      lines << "🔴 *Removed (#{removed.size}):*"
      lines << removed.first(20).map { |s| "`#{s}`" }.join(" ")
      lines << "_+ #{removed.size - 20} more_" if removed.size > 20
    end

    post_message(lines.join("\n"))
  rescue => e
    Rails.logger.error("[TelegramNotifier:#{@asset_type}] watchlist change: #{e.message}")
  end

  private

  def configured?
    @token.present? && @chat_ids.any?
  end

  # Accepts a String ("111, 222"), an Array, or a single id; returns a clean list.
  def normalize_chat_ids(value)
    Array(value)
      .flat_map { |v| v.to_s.split(/[,\s]+/) }
      .map(&:strip)
      .reject(&:empty?)
      .uniq
  end

  def format_message(signal)
    emoji = signal.signal_type == "BUY" ? "🟢" : "🔴"
    score_display = signal.score ? "#{(signal.score * 100).round}%" : "N/A"
    asset_tag = signal.asset_type == "stock" ? "🇮🇩 IDX" : "💰 CRYPTO"
    display_symbol = signal.asset_type == "stock" ? signal.symbol.sub(".JK", "") : signal.symbol
    meta = signal.metadata || {}
    currency = signal.asset_type == "stock" ? "Rp " : "$"

    msg = +"#{emoji} *#{signal.signal_type}* — #{display_symbol} (#{asset_tag})\n"
    msg << "Score: *#{score_display}*"

    if meta["confluence"]
      msg << " (#{meta["confluence"]} indicators)\n"
      msg << "Trend: `#{meta["trend"]}` | ATR: `#{meta["atr_pct"]}%`\n"

      if meta["entry_price"]
        entry = meta["entry_price"].to_f
        sl    = meta["sl_price"].to_f
        tp    = meta["tp_price"].to_f

        msg << "\n*🎯 Trade Levels:*\n"
        msg << "  Entry: `#{currency}#{format_price(entry)}`\n"
        msg << "  SL:    `#{currency}#{format_price(sl)}` (`#{meta["sl_pct"]}%`)\n"
        msg << "  TP:    `#{currency}#{format_price(tp)}` (`+#{meta["tp_pct"].to_f.abs}%`)\n"
        msg << "  R:R    `1:#{meta["risk_reward"]}`\n"
      end

      msg << "\n*Signals aligned:*\n"
      Array(meta["checks"]).first(8).each do |c|
        arrow = c["dir"] == "bullish" ? "↑" : "↓"
        msg << "  #{arrow} `#{c["name"]}` @ `#{c["tf"]}`\n"
      end
    else
      msg << "\nStrategy: `#{signal.strategy}`\n"
      tf = meta["timeframe"]
      msg << "Timeframe: `#{tf}`\n" if tf
    end

    msg << "\nTime: #{signal.fired_at.strftime("%Y-%m-%d %H:%M UTC")}"
    msg
  end

  def format_ai_recommendation(signal, label, reason)
    asset_tag      = signal.asset_type == "stock" ? "🇮🇩 IDX" : "💰 CRYPTO"
    display_symbol = signal.asset_type == "stock" ? signal.symbol.sub(".JK", "") : signal.symbol
    currency       = signal.asset_type == "stock" ? "Rp " : "$"
    meta           = signal.metadata || {}
    score_display  = signal.score ? "#{(signal.score * 100).round}%" : "N/A"

    msg = +"🤖 *Rekomendasi AI* — #{display_symbol} (#{asset_tag})\n"
    msg << "*#{label}*\n"
    msg << "_karena #{reason}_\n\n"
    msg << "Score: *#{score_display}*\n"

    if meta["entry_price"]
      entry = meta["entry_price"].to_f
      sl    = meta["sl_price"].to_f
      tp    = meta["tp_price"].to_f

      msg << "\n*🎯 Trade Levels:*\n"
      msg << "  Entry: `#{currency}#{format_price(entry)}`\n"
      msg << "  SL:    `#{currency}#{format_price(sl)}` (`#{meta["sl_pct"]}%`)\n"
      msg << "  TP:    `#{currency}#{format_price(tp)}` (`+#{meta["tp_pct"].to_f.abs}%`)\n"
      msg << "  R:R    `1:#{meta["risk_reward"]}`\n"
    end

    msg << "\nTime: #{signal.fired_at.strftime("%Y-%m-%d %H:%M UTC")}"
    msg
  end

  def format_price(val)
    if val >= 1000
      val.round.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    elsif val >= 1
      val.round(2).to_s
    else
      val.round(6).to_s
    end
  end

  def post_message(text)
    # Broadcast to every recipient; one bad chat id must not block the others.
    @chat_ids.each do |chat_id|
      begin
        Http.post_json(
          "#{API_BASE}/bot#{@token}/sendMessage",
          { chat_id: chat_id, text: text, parse_mode: "Markdown" }
        )
      rescue => e
        # Telegram delivery is best-effort; never let it break signal processing.
        Rails.logger.error("[TelegramNotifier:#{@asset_type}] chat #{chat_id}: #{e.class}: #{e.message}")
      end
    end
  end
end
