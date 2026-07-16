require "test_helper"

class HttpTest < ActiveSupport::TestCase
  test "RetryableError is a kind of Http::Error" do
    assert Http::RetryableError < Http::Error
  end

  test "errors carry an optional status code" do
    err = Http::Error.new("boom", code: 418)
    assert_equal 418, err.code
    assert_nil Http::RetryableError.new("timeout").code
  end
end
