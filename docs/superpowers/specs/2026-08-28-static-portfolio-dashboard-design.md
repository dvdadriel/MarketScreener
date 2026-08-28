# Static portfolio dashboard (React + Vercel + Supabase)

## Tujuan

Dashboard IdxScreener perlu online 24/7 untuk ditunjukkan ke recruiter, tanpa
bergantung pada hosting Ruby yang hidup terus (Render/Fly/Koyeb semua minta
kartu kredit yang tidak bisa dipenuhi). Solusi: pindahkan **tampilan
read-only** dashboard ke frontend statis (React) yang query langsung ke
Supabase, deploy ke Vercel (gratis, tanpa kartu).

Rails tetap ada, tapi cuma sebagai mesin batch job (jalan di GitHub Actions,
sudah dikerjakan sebelumnya) — bukan web server publik.

## Di luar scope (sengaja tidak disentuh)

- Halaman `/idx_universe` (upload/hapus custom ticker) — tetap di Rails, tidak
  dipublikasikan, dipakai manual lokal kalau perlu.
- Halaman `/analysis` (live deep-analysis + LLM narrative) — tetap Ruby, tidak
  pindah ke web. Cara akses ke depan (Telegram, CLI, dll) itu keputusan
  terpisah, bukan bagian pekerjaan ini.
- Autentikasi/login — dashboard publik read-only, tidak ada data sensitif
  (tidak ada kredensial akun trading real, semua paper trading).

## Arsitektur

```
GitHub Actions (Ruby, harian)
        │  tulis hasil scan/momentum/paper-trade ke Supabase
        ▼
Supabase (Postgres + PostgREST auto-API, RLS read-only utk anon)
        ▲  fetch langsung, client-side, pakai anon key
        │
React (Vite) — static build
        │
Vercel (hosting statis, gratis, tanpa kartu)
```

Tidak ada backend custom baru. Tidak ada Vercel serverless function. React
manggil Supabase REST langsung dari browser.

## Sumber data

Query langsung (tanpa view baru, tinggal filter/order/limit dari tabel yang
sudah ada, RLS SELECT-only):

| Data dashboard | Tabel | Query |
|---|---|---|
| Trading signals terbaru | `trading_signals` | `asset_type=eq.stock&order=fired_at.desc&limit=50` |
| Swing picks 24 jam | `trading_signals` | `strategy=eq.SWING_PICK&fired_at=gte.<24h ago>&order=...` |
| Open paper trades | `paper_trades` | `asset_type=eq.stock&status=eq.open&order=entry_at.desc&limit=20` |
| Status market IDX | — | dihitung di JS dari jam WIB saat ini vs jadwal bursa (09:00–16:00 WIB, Senin–Jumat), tidak perlu ke DB |

Butuh 1 view Postgres baru (agregat sederhana, bukan path-dependent):

| View | Menggantikan | Isi |
|---|---|---|
| `latest_candle_closes` | `Candle.latest_closes` | `DISTINCT ON (symbol) ...` per `timeframe`/`asset_type`, urut `opened_at DESC` |

Butuh 2 tabel ringkasan baru, **diisi Ruby** (bukan SQL), karena
perhitungannya path-dependent (equity curve, rebalancing, drawdown,
Sharpe/profit-factor):

| Tabel baru | Diisi oleh | Kapan |
|---|---|---|
| `momentum_tracker_summary` (1 baris, upsert) | `MomentumPaperTracker#call` | Ditambahkan ke `idx:snapshot` (setelah momentum snapshot harian) |
| `paper_trade_stats_summary` (1 baris per `asset_type`, upsert) | `PaperTradeStats.for(asset_type)` | Ditambahkan ke task yang sama |

Kolom kedua tabel ini = persis key dari hash yang sudah dikembalikan
`MomentumPaperTracker#call` / `PaperTradeStats#call` (lihat kode) — supaya
tidak ada terjemahan/transformasi tambahan, cukup `to_h` → upsert.

## Keamanan (RLS)

Supabase expose seluruh schema `public` lewat REST kalau RLS tidak aktif.
Sebelum frontend dibuat:

1. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` di **semua** tabel `public`
   (default deny)
2. Policy `SELECT`-only untuk role `anon`, hanya di tabel/view yang dipakai
   dashboard: `trading_signals`, `paper_trades`, `latest_candle_closes`,
   `momentum_tracker_summary`, `paper_trade_stats_summary`
3. Tabel lain (termasuk tabel Solid Queue/Cache/Cable yang kini berbagi
   database yang sama — lihat Fase 1.3 plan) otomatis tetap tertutup karena
   default deny

## Komponen frontend

Satu halaman (mirror `dashboard#index`), React + Vite, tanpa router (tidak
perlu — cuma 1 halaman):

- `App.tsx` — layout, fetch semua data saat mount
- `lib/supabase.ts` — client Supabase (anon key dari env var Vercel)
- Komponen per section: `SignalsTable`, `SwingPicks`, `MomentumSummary`,
  `PaperTradeStats`, `OpenTrades` — masing-masing terima data via props,
  tidak fetch sendiri-sendiri (satu fetch batch di `App`, supaya gampang
  handle loading/error sekali di satu tempat)

## Error handling

- Fetch gagal (Supabase down/network) → tampilkan pesan error per section,
  bukan blank page — tiap komponen terima `data | null`, render fallback kalau
  `null`
- Data kosong (belum ada snapshot hari itu) → sudah pola lama di Rails view
  ("belum ada snapshot..."), dipertahankan sama di React

## Testing

- View `latest_candle_closes`: bandingkan output lewat `psql` manual vs
  `Candle.latest_closes` Ruby, pastikan sama untuk beberapa simbol
- Upsert `momentum_tracker_summary`/`paper_trade_stats_summary`: 1 assert
  sederhana di test Ruby yang sudah ada untuk task `idx:snapshot` — pastikan
  baris ter-upsert dengan kolom sesuai hash aslinya
- Frontend: smoke test manual di browser (sesuai gaya proyek ini, tanpa
  framework test tambahan)
