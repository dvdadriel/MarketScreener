# Poll perintah Telegram tiap menit (getUpdates short-poll — service lokal tanpa
# URL publik, jadi webhook bukan opsi). Latensi balasan maks ~60 detik.
class TelegramPollerJob < ApplicationJob
  queue_as :realtime

  def perform
    svc = TelegramCommandService.new
    return unless svc.configured?   # tanpa TELEGRAM_ADMIN_CHAT_ID: bot mati total

    svc.fetch_updates.each { |u| svc.process(u) }
  end
end
