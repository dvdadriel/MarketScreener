require "test_helper"
require "ostruct"

class NvidiaNimClientTest < ActiveSupport::TestCase
  def with_key(val)
    prev = ENV["NVIDIA_API_KEY"]
    ENV["NVIDIA_API_KEY"] = val
    yield
  ensure
    ENV["NVIDIA_API_KEY"] = prev
  end

  # Override Http.post_json with `impl` (a proc) for the block, then restore.
  def stub_post_json(impl)
    singleton = Http.singleton_class
    orig = Http.method(:post_json)
    singleton.define_method(:post_json) { |*a, **k| impl.call }
    yield
  ensure
    singleton.define_method(:post_json) { |*a, **k| orig.call(*a, **k) }
  end

  def resp(content)
    OpenStruct.new(body: { choices: [ { message: { content: content } } ] }.to_json)
  end

  test "returns nil when API key is blank" do
    with_key("") do
      assert_nil NvidiaNimClient.new.chat(system: "s", user: "u")
    end
  end

  test "parses assistant text" do
    with_key("nvapi-test") do
      stub_post_json(-> { resp("hasil analisis") }) do
        assert_equal "hasil analisis", NvidiaNimClient.new.chat(system: "s", user: "u")
      end
    end
  end

  test "parses json content when json: true" do
    with_key("nvapi-test") do
      stub_post_json(-> { resp({ score: 0.5, label: "bullish" }.to_json) }) do
        assert_equal 0.5, NvidiaNimClient.new.chat(system: "s", user: "u", json: true)["score"]
      end
    end
  end

  test "returns nil on Http error" do
    with_key("nvapi-test") do
      stub_post_json(-> { raise Http::RetryableError.new("boom") }) do
        assert_nil NvidiaNimClient.new.chat(system: "s", user: "u")
      end
    end
  end

  test "falls back to next model when the first one fails" do
    calls = 0
    impl = lambda do
      calls += 1
      raise Http::RetryableError.new("down") if calls == 1   # model #1 unallocated
      resp("dari fallback")
    end
    with_key("nvapi-test") do
      stub_post_json(impl) do
        assert_equal "dari fallback", NvidiaNimClient.new.chat(system: "s", user: "u")
      end
    end
    assert_equal 2, calls, "should try the second model after the first fails"
  end
end
