class ApplicationJob < ActiveJob::Base
  # Retry transient network failures (timeouts, connection resets, HTTP 429/5xx)
  # with exponential backoff. Jobs that loop over many symbols handle rate limits
  # inline (abort the batch early); this is the safety net for everything else.
  retry_on Http::RetryableError, wait: :polynomially_longer, attempts: 5

  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
