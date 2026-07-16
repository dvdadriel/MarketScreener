# Ranks a BUY batch (one asset_type) via NVIDIA NIM. Returns:
#   { status: :ok,          picks: [ { signal:, reason: } ] }  # AI endorsed 1-3
#   { status: :none,        picks: [] }                         # AI endorsed none
#   { status: :unavailable, picks: [] }                         # NIM down / empty input
class AiRecommenderService
  MAX_PICKS = 3

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Kamu analis trading. Dari daftar sinyal BUY berikut, pilih maksimal 3 setup TERBAIK.
    Prioritaskan setup di mana score internal, rating TradingView, dan sentimen berita sejalan.
    Balas HANYA JSON: {"picks":[{"id":<id>,"reason":"<satu kalimat alasan konkret Bahasa Indonesia>"}]}.
    Kosongkan picks kalau tidak ada yang meyakinkan. Tanpa basa-basi, tanpa disclaimer.
  PROMPT

  def initialize(signals, tv_ratings: {})
    @signals = signals
    @tv      = tv_ratings || {}
  end

  def call
    return unavailable if @signals.empty?

    raw = NvidiaNimClient.new.chat(system: SYSTEM_PROMPT, user: payload.to_json, json: true, max_tokens: 512)
    return unavailable if raw.nil?

    by_id = @signals.index_by(&:id)
    picks = Array(raw["picks"]).filter_map do |p|
      next unless p.is_a?(Hash)
      sig = by_id[p["id"]]
      next unless sig
      { signal: sig, reason: p["reason"].to_s.strip }
    end.first(MAX_PICKS)

    picks.empty? ? { status: :none, picks: [] } : { status: :ok, picks: picks }
  rescue => e
    Rails.logger.warn("[AiRecommenderService] #{e.class}: #{e.message}")
    unavailable
  end

  private

  def unavailable = { status: :unavailable, picks: [] }

  def payload
    @signals.map do |s|
      meta = s.metadata || {}
      {
        id:             s.id,
        symbol:         s.symbol,
        setup:          SetupLabeler.label(s),
        score:          s.score,
        tradingview:    @tv[s.symbol],
        news_sentiment: meta["news_sentiment"],
        entry:          meta["entry_price"],
        sl:             meta["sl_price"],
        tp:             meta["tp_price"],
        rr:             meta["risk_reward"]
      }
    end
  end
end
