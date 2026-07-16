# Scores news sentiment for a symbol via NVIDIA NIM. Returns nil when there are
# no headlines or the LLM is unavailable/malformed — sentiment is an optional
# annotation on a signal, never a blocker.
class NewsSentimentService
  SYSTEM = <<~PROMPT.freeze
    Kamu analis sentimen pasar. Nilai sentimen dari daftar headline berikut untuk aset yang disebut.
    Keluarkan HANYA JSON dengan bentuk persis:
    {"score": <angka desimal -1..1>, "label": "bullish|neutral|bearish", "reason": "<1 kalimat singkat>"}
    score negatif = bearish, positif = bullish, sekitar 0 = neutral. Jangan tambah teks lain di luar JSON.
  PROMPT

  def initialize(client: NvidiaNimClient.new, fetcher: NewsFetcher.new)
    @client  = client
    @fetcher = fetcher
  end

  def score(symbol:, asset_type:)
    titles = @fetcher.headlines(symbol: symbol, asset_type: asset_type)
    return nil if titles.empty?

    result = @client.chat(
      json:   true,
      system: SYSTEM,
      user:   "Aset: #{symbol}\nHeadlines:\n- #{titles.join("\n- ")}"
    )
    return nil unless result.is_a?(Hash) && result["score"].is_a?(Numeric) && result["label"]

    {
      "score"           => result["score"].to_f.clamp(-1.0, 1.0).round(3),
      "label"           => result["label"].to_s,
      "reason"          => result["reason"].to_s,
      "headlines_count" => titles.size
    }
  end
end
