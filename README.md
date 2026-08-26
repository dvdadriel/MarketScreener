# CryptoRadar

Screener saham IDX dengan **backtesting walk-forward, paper trading, dan alert Telegram**. Rails 8.1 + PostgreSQL + Solid Queue/Cache/Cable, jalan sebagai service always-on lokal (macOS LaunchAgent `com.cryptoradar`).

> **Status:** fokus saham IDX; crypto dinonaktifkan (`CRYPTO_ENABLED`, default off).
> Strategi aktif dalam observasi: **cross-sectional momentum** (forward tracking harian,
> gate promosi 8 minggu). Hasil pengukuran beserta asumsi dan batasannya:
> [`docs/backtest-results.md`](docs/backtest-results.md).

## Masalah yang diselesaikan

Screener saham yang tersedia umumnya menjawab "saham apa yang sedang bergerak", bukan "apakah aturan seleksi saya benar-benar bekerja". Keduanya pertanyaan berbeda, dan yang kedua butuh infrastruktur: histori candle, simulasi biaya, validasi walk-forward, dan pencatatan hasil ke depan agar tidak bisa diakali sesudahnya.

Project ini dibangun untuk menjawab pertanyaan kedua. Fokusnya bukan menghasilkan sinyal, tapi **mengukur apakah sinyalnya layak dipercaya** — dan menahan diri dari mempertaruhkan uang sebelum bisa dibuktikan.

Hasilnya: sistemnya bekerja, dan **jawabannya belum**. Lihat bagian hasil.

## Hasil

Angka lengkap, reproducible, beserta seluruh batasannya:
**[`docs/backtest-results.md`](docs/backtest-results.md)**

Ringkasan yang paling representatif:

| | |
|---|---|
| Walk-forward terbaik (730 hari, buffer 20) | ret **+8,92%**, alpha vs IHSG **+24,65%**, maxDD 10,95%, Sharpe 0,73 |
| Walk-forward terpanjang (1095 hari, buffer 15) | ret **−12,80%**, alpha **−2,18%**, maxDD 14,50% |
| Forward tracking paper (21 hari-snapshot) | **+0,00%** — 100% cash karena regime risk-off, sementara IHSG +4,42% |
| Paper trading (16.879 trade closed, 3 bulan) | win rate **7,76%**, profit factor **0,784** |

Kontribusi utama strategi ini adalah **menghindari kerugian**, bukan mengejar keuntungan — alpha positif besar di jendela 1–2 tahun karena IHSG turun lebih dalam. Tapi profit factor di bawah 1, jendela terpanjang rugi, dan forward tracking-nya nol. Dokumen hasil menjelaskan mengapa, termasuk temuan bahwa **89% kerugian paper trading berasal dari satu strategi** dan satu strategi lain menghasilkan 13.481 trade dengan win rate 0,6%.

Semua angka adalah backtest dan paper trading. **Tidak ada uang sungguhan yang pernah dipertaruhkan.** Ini bukan nasihat finansial.

## Arsitektur singkat

- **Data**: candle Yahoo Finance (saham `.JK` + indeks `^JKSE`) & Binance (crypto) → tabel `candles`.
- **Strategi**: `MomentumRankingService` (aktif, observasi — momentum residual beta-adjusted terhadap `^JKSE`) · `SignalConfluenceService` (paper baseline, alert di-mute) · `IdxScannerService` (SWING_PICK) · `SqueezeBreakoutService` (crypto-only; terbukti rugi untuk saham — lihat dokumen hasil).
- **Gate**: `IdxMarketState` — regime IHSG (MA50/MA200) dengan histeresis konfirmasi 5 hari, **fail-closed** saat data tak terkonfirmasi.
- **Validasi**: `BacktestService` (per-trade, walk-forward via `as_of:`/`offset_days:`) & `MomentumBacktestService` (portofolio, rebalance bulanan, fee/slippage/sizing, buffer zone).
- **Forward tracking**: `MomentumSnapshotJob` (harian) → `MomentumPaperTracker` → laporan rekonsiliasi mingguan ke Telegram. `MomentumGateEvaluator` menilai kriteria promosi 8 minggu secara otomatis.
- **Ops**: `HealthCheck` + `HealthMonitorJob` (termasuk watchdog kalau job snapshot harian gagal senyap) · `EvidenceBackupService` (pg_dump bukti harian, rotasi 30 hari).
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
bin/rails test                                        # suite (wajib hijau sebelum commit)
bin/rails 'momentum:buffer_sweep[extended]'           # walk-forward 3 jendela x 4 buffer
bin/rails 'momentum:backtest[365,extended,0,15]'      # backtest portofolio momentum
bin/rails 'backtest:run[730,all,extended,0.4,0.1,1.0]' # backtest per-trade lintas strategi
bin/rails 'momentum:rank[extended]'                   # peringkat momentum hari ini + regime
bin/rails momentum:paper                              # status forward tracking vs IHSG
```

## Batasan yang diketahui

Selain batasan metodologis di [`docs/backtest-results.md`](docs/backtest-results.md):

- **Run backtest pertama memberi angka yang salah tanpa peringatan.** Histori candle diambil on-demand, sehingga cache dingin menghasilkan angka berbeda dari cache hangat — selisih 8,2 poin persentase teramati. Guard `MAX_MISSING_SHARE = 0.10` tidak menyala; toleransi itu terlalu longgar.
- **Max drawdown di dashboard salah hitung** (menampilkan −4152%, yang mustahil untuk kurva ekuitas) — dihitung dari penjumlahan `pnl_pct` per trade, bukan peak-to-trough yang di-compound.
- **`CONFLUENCE_BEARISH` rusak, bukan sekadar merugi** — 13.481 trade dengan win rate 0,6%, mendominasi 80% volume dan membuat statistik agregat tidak bermakna.
- **Belum di-deploy sebagai layanan publik.** Berjalan sebagai service lokal always-on; tidak ada autentikasi multi-user di dashboard.
- **Sampel forward tracking masih pendek** — gate promosi 8 minggu belum tuntas.
- **`pg_dump` stderr hanya baris pertama yang masuk log**, sehingga diagnosis kegagalan backup terbatas.
- **Tidak ada test untuk `check_coverage!`** — guard yang menjaga kelengkapan data justru belum diuji.

## Lisensi

MIT — lihat [LICENSE](LICENSE).
