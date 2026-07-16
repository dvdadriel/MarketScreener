require "json"

# Thin OpenAI-compatible client for NVIDIA NIM hosted inference.
# Degrades to nil (never raises to callers) so LLM features stay optional:
# no API key, or NIM/parse failure => the feature is simply skipped.
class NvidiaNimClient
  URL = "https://integrate.api.nvidia.com/v1".freeze

  # Fallback chain: dicoba berurutan, model pertama yang berhasil menang.
  # DeepSeek primary; kalau gagal ke gpt-oss; Nemotron (NVIDIA sendiri, paling
  # stabil) sebagai jaring pengaman terakhir.
  DEFAULT_MODEL = "nvidia/nemotron-3-ultra-550b-a55b".freeze
  MODELS = %w[
    deepseek-ai/deepseek-v4-pro
    openai/gpt-oss-120b
    nvidia/nemotron-3-ultra-550b-a55b
  ].freeze

  def initialize
    @key    = ENV["NVIDIA_API_KEY"].to_s
    # Override lewat NVIDIA_NIM_MODELS (comma-separated, urut prioritas).
    # DEFAULT_MODEL selalu diikutkan sebagai fallback terakhir.
    listed  = ENV["NVIDIA_NIM_MODELS"].to_s.split(",").map(&:strip).reject(&:empty?)
    @models = ((listed.empty? ? MODELS : listed) + [ DEFAULT_MODEL ]).uniq
  end

  def configured? = !@key.empty?

  # Returns the assistant text (String), or a parsed Hash when json: true,
  # or nil when every model in the chain fails (missing key, HTTP error,
  # unparseable body). Mencoba tiap model sampai satu berhasil.
  def chat(system:, user:, json: false, max_tokens: 512, timeout: 90)
    return nil unless configured?

    @models.each do |model|
      result = try_model(model, system:, user:, json:, max_tokens:, timeout:)
      return result unless result.nil?
    end
    nil
  end

  private

  # ponytail: chain dicoba sekuensial tiap call — kalau model teratas sering down,
  # cache "model sehat" per proses kalau latency jadi masalah.
  def try_model(model, system:, user:, json:, max_tokens:, timeout:)
    payload = {
      model:       model,
      temperature: 0.3,
      max_tokens:  max_tokens,
      messages: [
        { role: "system", content: system },
        { role: "user",   content: user }
      ]
    }
    payload[:response_format] = { type: "json_object" } if json

    resp = Http.post_json("#{URL}/chat/completions", payload,
      headers: { "Authorization" => "Bearer #{@key}" },
      read_timeout: timeout)

    content = JSON.parse(resp.body).dig("choices", 0, "message", "content")
    return nil if content.nil? || content.strip.empty?

    json ? JSON.parse(content) : content
  rescue Http::Error, JSON::ParserError => e
    Rails.logger.warn("[NvidiaNimClient] #{model}: #{e.class}: #{e.message}")
    nil
  end
end
