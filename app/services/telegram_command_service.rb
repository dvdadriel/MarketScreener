# Command bot Telegram (plan #3). KEAMANAN — tidak bisa ditawar:
#   1. Hanya chat TELEGRAM_ADMIN_CHAT_ID yang dilayani; lainnya di-drop + log.
#   2. Allowlist eksplisit command → method. TIDAK ADA eval/shell/interpolasi.
#   3. Argumen di-parse ketat (enum/angka saja). Rate limit 10 command/menit.
# Polling via TelegramPollerJob (getUpdates, offset di Solid Cache — survive restart).
class TelegramCommandService
  API_BASE   = TelegramNotifier::API_BASE
  OFFSET_KEY = "telegram:last_update_id".freeze
  MUTE_KEY   = "telegram:alerts_muted_until".freeze
  RATE_LIMIT = 10   # command per menit

  UNIVERSES = {
    "lq45"     => -> { IdxMarket::WATCHLIST },
    "extended" => -> { IdxMarket::EXTENDED_WATCHLIST },
    "all"      => -> { IdxUniverseService.all }
  }.freeze

  def self.alerts_muted?
    until_ts = Rails.cache.read(MUTE_KEY)
    until_ts.present? && Time.current.to_i < until_ts
  end

  def initialize
    creds  = Rails.application.credentials.telegram || {}
    scope  = creds[:stock] || creds
    @token = scope[:bot_token] || ENV["TELEGRAM_STOCK_BOT_TOKEN"] || ENV["TELEGRAM_BOT_TOKEN"]
    # Admin = chat_ids PERTAMA di credentials (pemilik). ENV sebagai override opsional.
    @admin = ENV["TELEGRAM_ADMIN_CHAT_ID"].presence || first_credential_chat_id(scope)
  end

  def configured? = @token.present? && @admin.present?

  # Format sama dengan TelegramNotifier#normalize_chat_ids: string "111, 222" / array.
  def first_credential_chat_id(scope)
    raw = scope[:chat_ids] || scope[:chat_id] || ENV["TELEGRAM_STOCK_CHAT_ID"] || ENV["TELEGRAM_CHAT_ID"]
    Array(raw).flat_map { |v| v.to_s.split(/[,\s]+/) }.map(&:strip).reject(&:empty?).first.to_s
  end

  def fetch_updates
    offset = Rails.cache.read(OFFSET_KEY).to_i
    resp = Http.get_json("#{API_BASE}/bot#{@token}/getUpdates",
                         query: { offset: offset + 1, timeout: 0 })
    Array(resp["result"])
  rescue Http::Error => e
    Rails.logger.warn("[TelegramCommand] getUpdates: #{e.message}")
    []
  end

  def process(update)
    # Selalu ack update (termasuk yang unauthorized) — kalau tidak, ia dipoll selamanya.
    Rails.cache.write(OFFSET_KEY, update["update_id"].to_i)

    msg     = update["message"] || {}
    chat_id = msg.dig("chat", "id").to_s
    text    = msg["text"].to_s.strip
    return if text.empty?

    unless chat_id == @admin
      Rails.logger.warn("[TelegramCommand] DROP unauthorized chat #{chat_id}: #{text.truncate(50)}")
      return
    end
    return reply(chat_id, "⏳ Rate limit — coba lagi sebentar.") if rate_limited?

    Rails.logger.info("[TelegramCommand] #{text}")
    reply(chat_id, dispatch(text))
  end

  # Satu format daftar ranking untuk /rank manual maupun RankReportJob — jangan
  # duplikasi teksnya di dua tempat.
  def self.format_rank(picks, blocked)
    header = if blocked
      "🛑 *Regime RISK-OFF → CASH* — watchlist, JANGAN beli dulu\n_#{IdxMarketState.reason}_"
    else
      "📈 *Top #{picks.size} Momentum* (regime risk-on)"
    end
    lines = [ header ]
    picks.each_with_index { |p, i| lines << "#{i + 1}. *#{p[:symbol].sub('.JK', '')}* #{format('%+.1f%%', p[:momentum] * 100)} · Rp #{p[:last_close].to_i}" }
    lines.join("\n")
  end

  private

  # Allowlist eksplisit — satu-satunya jalur dari teks Telegram ke kode.
  def dispatch(text)
    cmd, arg = text.split(/\s+/, 2)
    case cmd
    when "/rank"    then cmd_rank(arg)
    when "/health"  then cmd_health
    when "/status"  then cmd_status
    when "/summary" then DailySummaryJob.perform_later; "📨 Daily summary dikirim."
    when "/mute"    then cmd_mute(arg)
    when "/unmute"  then Rails.cache.delete(MUTE_KEY); "🔔 Alert aktif lagi."
    when "/help"    then help_text
    else "Perintah tak dikenal. /help untuk daftar."
    end
  rescue => e
    Rails.logger.error("[TelegramCommand] #{cmd}: #{e.class}: #{e.message}")
    "⚠️ Gagal menjalankan #{cmd}: #{e.class}"
  end

  def cmd_rank(arg)
    universe = UNIVERSES[arg.to_s.strip.presence || "lq45"]
    return "Universe: lq45 | extended | all" unless universe

    blocked = IdxMarketState.long_blocked?
    # Risk-off: tetap tampilkan ranking sebagai WATCHLIST (bukan sinyal beli) —
    # ignore_regime hanya untuk lihat, aksi nyata (snapshot/paper) tetap ter-gate.
    picks = MomentumRankingService.new(symbols: universe.call, ignore_regime: blocked).call
    return "Tidak ada pick (data kurang)." if picks.empty?

    self.class.format_rank(picks, blocked)
  end

  def cmd_health
    r = HealthCheck.run
    icon = r.healthy? ? "✅" : "🩺"
    lines = [ "#{icon} *Health: #{r.healthy? ? 'ok' : 'degraded'}*" ]
    r.checks.each { |name, c| lines << "#{c[:ok] ? '✓' : '✗'} `#{name}` — #{c[:detail]}" }
    lines.join("\n")
  end

  def cmd_status
    r = MomentumPaperTracker.new.call
    return "Belum ada data tracking." if r[:tracked_days].zero?
    alpha = r[:ihsg_return] ? (r[:total_return] - r[:ihsg_return]).round(2) : nil
    [ "📊 *Momentum paper* (#{r[:inception]} → #{r[:as_of]}, #{r[:tracked_days]}h)",
      "Return: #{format('%+.2f%%', r[:total_return])} · maxDD -#{r[:max_drawdown]}% · Alpha: #{alpha ? format('%+.2f%%', alpha) : '-'}",
      "Regime: `#{r[:regime_today]}` · #{r[:holdings].any? ? r[:holdings].map { |s| s.sub('.JK', '') }.join(', ') : 'CASH'}" ].join("\n")
  end

  def cmd_mute(arg)
    hours = arg.to_s[/\A\d{1,3}\z/]&.to_i || 24
    Rails.cache.write(MUTE_KEY, hours.hours.from_now.to_i, expires_in: hours.hours)
    "🔕 Alert dibungkam #{hours} jam (laporan mingguan & health tetap jalan). /unmute untuk batal."
  end

  def help_text
    [ "*Perintah:*",
      "/rank [lq45|extended|all] — top-10 momentum + regime",
      "/status — equity paper momentum vs IHSG",
      "/health — status sistem",
      "/summary — kirim daily summary sekarang",
      "/mute [jam] · /unmute — bungkam alert sinyal" ].join("\n")
  end

  def rate_limited?
    key = "telegram:rate:#{Time.current.to_i / 60}"
    count = Rails.cache.increment(key, 1, expires_in: 2.minutes) || 1
    count > RATE_LIMIT
  end

  def reply(chat_id, text)
    Http.post_json("#{API_BASE}/bot#{@token}/sendMessage",
                   { chat_id: chat_id, text: text, parse_mode: "Markdown" })
  rescue => e
    Rails.logger.error("[TelegramCommand] reply: #{e.class}: #{e.message}")
  end
end
