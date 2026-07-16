# Human "pembeda" label for a signal's setup type. Pure; used by both the AI
# prompt and the Telegram message so wording stays identical.
module SetupLabeler
  module_function

  def label(signal)
    strategy = signal.strategy.to_s
    return "Squeeze Breakout" if strategy == "SQUEEZE_BREAKOUT"
    return trend_label(signal) if strategy.start_with?("CONFLUENCE")
    strategy
  end

  def trend_label(signal)
    rsi = rsi_from(signal)
    return "Jenuh Jual (Oversold)"    if rsi && rsi <= 35
    return "Jenuh Beli (Overbought)"  if rsi && rsi >= 65
    "Trend Confluence"
  end

  # metadata["checks"] is [{ name:, dir:, tf: }, ...]; the RSI check's name is
  # "rsi(28.5)". Keys may be strings (from DB JSON) or symbols (in-memory).
  def rsi_from(signal)
    checks = signal.metadata&.dig("checks") || signal.metadata&.dig(:checks) || []
    check  = checks.find { |c| (c["name"] || c[:name]).to_s.start_with?("rsi(") }
    return nil unless check
    (check["name"] || check[:name])[/rsi\(([\d.]+)\)/, 1]&.to_f
  end
end
