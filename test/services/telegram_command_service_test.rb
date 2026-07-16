require "test_helper"

class TelegramCommandServiceTest < ActiveSupport::TestCase
  ADMIN = "111222333".freeze

  def with_env
    prev_admin = ENV["TELEGRAM_ADMIN_CHAT_ID"]
    prev_token = ENV["TELEGRAM_BOT_TOKEN"]
    ENV["TELEGRAM_ADMIN_CHAT_ID"] = ADMIN
    ENV["TELEGRAM_BOT_TOKEN"] = "test-token"
    # Test env pakai null_store — swap ke MemoryStore agar offset/mute bisa diuji.
    store = ActiveSupport::Cache::MemoryStore.new
    orig_cache = Rails.method(:cache)
    Rails.define_singleton_method(:cache) { store }
    yield
  ensure
    ENV["TELEGRAM_ADMIN_CHAT_ID"] = prev_admin
    ENV["TELEGRAM_BOT_TOKEN"] = prev_token
    Rails.define_singleton_method(:cache, orig_cache)
  end

  # Tangkap balasan keluar; blokir HTTP sungguhan.
  def capture_replies
    sent = []
    singleton = Http.singleton_class
    orig = Http.method(:post_json)
    singleton.define_method(:post_json) { |_url, payload, **| sent << payload[:text] }
    yield sent
  ensure
    singleton.define_method(:post_json) { |*a, **k| orig.call(*a, **k) }
  end

  def update(chat_id:, text:, id: 1)
    { "update_id" => id, "message" => { "chat" => { "id" => chat_id }, "text" => text } }
  end

  test "first_credential_chat_id picks first entry from comma string or array" do
    svc = TelegramCommandService.new
    assert_equal "777", svc.first_credential_chat_id({ chat_ids: "777, 888" })
    assert_equal "999", svc.first_credential_chat_id({ chat_id: [ "999", "111" ] })
  end

  test "drops messages from non-admin chat silently" do
    with_env do
      capture_replies do |sent|
        TelegramCommandService.new.process(update(chat_id: "999", text: "/health"))
        assert_empty sent
      end
    end
  end

  test "unknown command gets help hint, never executes" do
    with_env do
      capture_replies do |sent|
        TelegramCommandService.new.process(update(chat_id: ADMIN, text: "/rm -rf /"))
        assert_equal 1, sent.size
        assert_match(/tak dikenal/, sent.first)
      end
    end
  end

  test "/mute sets flag respected by alerts_muted? and /unmute clears it" do
    with_env do
      capture_replies do |_|
        TelegramCommandService.new.process(update(chat_id: ADMIN, text: "/mute 2"))
        assert TelegramCommandService.alerts_muted?
        TelegramCommandService.new.process(update(chat_id: ADMIN, text: "/unmute", id: 2))
        assert_not TelegramCommandService.alerts_muted?
      end
    end
  end

  test "acknowledges offset even for unauthorized updates" do
    with_env do
      capture_replies do |_|
        TelegramCommandService.new.process(update(chat_id: "999", text: "spam", id: 42))
        assert_equal 42, Rails.cache.read(TelegramCommandService::OFFSET_KEY)
      end
    end
  end

  test "/status replies with tracker summary" do
    MomentumSnapshot.create!(snapshot_date: Date.current, regime: "risk_off")
    with_env do
      capture_replies do |sent|
        TelegramCommandService.new.process(update(chat_id: ADMIN, text: "/status"))
        assert_match(/Momentum paper/, sent.first)
        assert_match(/risk_off/, sent.first)
      end
    end
  end
end
