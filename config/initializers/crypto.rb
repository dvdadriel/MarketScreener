# Master switch untuk fitur crypto. Default OFF — proyek sedang fokus saham IDX.
# Set CRYPTO_ENABLED=true untuk mengaktifkan lagi (dan uncomment price_poller_*
# di config/recurring.yml). Lihat guideline/feature.md.
CRYPTO_ENABLED = ENV.fetch("CRYPTO_ENABLED", "false") == "true"
