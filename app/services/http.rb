require "net/http"
require "json"

# Tiny wrapper around Net::HTTP that enforces timeouts and turns transient
# failures (timeouts, connection resets, HTTP 429/5xx) into Http::RetryableError
# so callers/jobs can back off and retry instead of hanging a worker.
module Http
  OPEN_TIMEOUT = 5   # seconds to establish the TCP/TLS connection
  READ_TIMEOUT = 15  # seconds to wait for the response body

  class Error < StandardError
    attr_reader :code

    def initialize(message, code: nil)
      super(message)
      @code = code
    end
  end

  # Raised for conditions worth retrying: timeouts, connection errors,
  # rate limiting (429) and server errors (5xx).
  class RetryableError < Error; end

  module_function

  def get(url, query: nil, headers: {}, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    uri = URI(url)
    uri.query = URI.encode_www_form(query) if query
    request(Net::HTTP::Get.new(uri), uri, headers, open_timeout, read_timeout)
  end

  def get_json(url, **opts)
    JSON.parse(get(url, **opts).body)
  end

  def post_json(url, payload, headers: {}, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    req.content_type = "application/json"
    req.body = JSON.generate(payload)
    request(req, uri, headers, open_timeout, read_timeout)
  end

  def request(req, uri, headers, open_timeout, read_timeout)
    headers.each { |k, v| req[k] = v }

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout

    response = http.request(req)

    case response
    when Net::HTTPSuccess
      response
    when Net::HTTPTooManyRequests
      raise RetryableError.new("HTTP 429 (rate limited) for #{uri.host}", code: 429)
    else
      code = response.code.to_i
      message = "HTTP #{response.code} for #{uri.host}"
      raise(code >= 500 ? RetryableError.new(message, code: code) : Error.new(message, code: code))
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, SocketError => e
    raise RetryableError.new("#{e.class}: #{e.message}")
  end
end
