# CryptoRadar

Screener saham IDX (dan crypto, saat diaktifkan) dengan paper trading, backtesting, dan
alert Telegram. Rails 8.1 + PostgreSQL + Solid Queue/Cache/Cable, jalan sebagai service
always-on lokal (macOS LaunchAgent `com.cryptoradar`).

> **Status:** fokus saham IDX; crypto dinonaktifkan (`CRYPTO_ENABLED`, default off).
> Strategi aktif dalam observasi: **cross-sectional momentum** (forward tracking harian,
> gate promosi 8 minggu). Dokumen arah & keputusan: [`guideline/`](guideline/).

## Arsitektur singkat

- **Data**: candle Yahoo Finance (saham `.JK` + indeks `^JKSE`) & Binance (crypto) → tabel `candles`.
- **Strategi**: `MomentumRankingService` (aktif, observasi) · `SignalConfluenceService` (paper baseline, alert di-mute) · `IdxScannerService` (SWING_PICK) · `SqueezeBreakoutService` (crypto-only; terbukti rugi utk saham).
- **Gate**: `IdxMarketState` — regime IHSG (MA50/MA200), **fail-closed** saat data tak terkonfirmasi.
- **Validasi**: `BacktestService` (per-trade, walk-forward via `as_of:`/`offset_days:`) & `MomentumBacktestService` (portofolio, rebalance bulanan, fee/slippage/sizing).
- **Forward tracking**: `MomentumSnapshotJob` (harian) → `MomentumPaperTracker` → laporan rekonsiliasi mingguan ke Telegram.
- **Telegram**: alert + command bot admin-only (`/rank` `/status` `/health` `/summary` `/mute`).

## Menjalankan

```bash
bin/setup                                  # deps + db
bin/dev                                    # dev (web + jobs + css)
# atau service produksi-lokal:
launchctl kickstart -k gui/$(id -u)/com.cryptoradar
```

Konfigurasi: `.env` (lihat `.env.example`) + `rails credentials:edit` (telegram bot/chat).
Health check: `GET /health` (dipantau `HealthMonitorJob` → Telegram).

## Perintah penting

```bash
bin/rails test                                      # suite (wajib hijau sebelum commit)
bin/rails "backtest:run[365,all,extended,0.4,0.1]"  # backtest per-trade (fee, slippage, sizing)
bin/rails "momentum:backtest[365,extended,0]"       # backtest portofolio momentum
bin/rails "momentum:rank[extended]"                 # peringkat momentum hari ini + regime
bin/rails momentum:paper                            # status forward tracking vs IHSG
```

Paper trading only — bukan nasihat finansial.
