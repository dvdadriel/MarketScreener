# IdxScreener — Rencana Deploy

> Update: repo ini (`CryptoScreener` secara lokal) sudah di-rename jadi
> **`dvdadriel/idx-screener`** di GitHub (lihat commit `refactor: unify the
> user-facing name to IdxScreener`) — jadi file ini sudah berada di repo yang
> tepat. Cukup pindahkan ke `docs/deploy-plan.md` kalau ingin nama file yang
> lebih pendek; tidak perlu pindah repo.

**Arsitektur yang dipilih (final):**

```
Supabase (Postgres)  ←──  GitHub Actions (job harian, gratis, repo publik)
        ↑
        │  REST API (PostgREST, RLS read-only)
        │
React statis (Vercel, gratis, tanpa kartu)  ←── idx.domain-anda.com
```

**Prinsipnya:** dashboard portofolio ini murni read-only, jadi tidak butuh server
Ruby yang hidup 24 jam sama sekali. Job harian (GitHub Actions) menulis ke Supabase;
frontend statis (Fase 3.5) baca langsung dari situ lewat REST API Supabase. Rails
cuma dipakai sebagai mesin batch job, tidak pernah di-deploy sebagai web service.

> **Fase 3 (Koyeb) di bawah ini sudah tidak diperlukan** untuk dashboard portofolio
> — dibiarkan di dokumen ini sebagai referensi kalau suatu saat butuh fitur
> interaktif (search live, upload ticker, dll) yang memang butuh Rails hidup.
> Jalur yang benar-benar dipakai sekarang ada di **Fase 3.5**.

---

## Fase 0 — Inventaris (kerjakan ini dulu)

Saya tidak bisa melihat isi repo IdxScreener dari sini. Jalankan ini dan catat
hasilnya; empat fase berikutnya bergantung padanya.

```bash
cd idx-screener

# Apa saja yang saat ini dijadwalkan Solid Queue?
cat config/recurring.yml

# Rake task apa yang sudah ada?
ls lib/tasks/ && grep -rn "^task\|namespace" lib/tasks/

# Rails 8 memisahkan primary/cache/queue/cable jadi beberapa database.
# Ini yang paling menentukan di Fase 1.
cat config/database.yml

# Solid Queue jalan di dalam Puma, atau proses terpisah?
grep -rn "SOLID_QUEUE_IN_PUMA\|solid_queue" config/ Procfile* 2>/dev/null

# Env var apa yang dibutuhkan aplikasi?
cat .env.example 2>/dev/null || grep -rhn "ENV\[" app/ lib/ config/ | sort -u
```

**Yang perlu Anda putuskan dari hasil di atas:**

1. Jadwal mana di `recurring.yml` yang harian → pindah ke GitHub Actions.
   Jadwal yang dipicu request → tetap di Solid Queue.
2. Apakah `database.yml` produksi memakai empat database terpisah. Kalau ya, lihat
   catatan multi-DB di Fase 1.

---

## Fase 1 — Supabase (Postgres)

### 1.1 Buat project

Region **Singapore** — paling dekat ke Jakarta dan ke region Singapore Render.

Simpan dua connection string yang berbeda; ini bukan detail sepele:

| Dipakai untuk | Port | Kenapa |
|---|---|---|
| Web service & GitHub Actions | **6543** (pooler, transaction mode) | Banyak koneksi pendek |
| Migrasi & `psql` manual | **5432** (direct) | Pooler tidak mendukung DDL dengan advisory lock |

### 1.2 Rails di belakang pooler

Pooler Supabase mode transaction **tidak mendukung prepared statements**. Tanpa
setelan ini aplikasi akan error dengan pesan yang menyesatkan soal
`prepared statement "aXX" already exists`:

```yaml
# config/database.yml — bagian production
production:
  primary:
    url: <%= ENV["DATABASE_URL"] %>
    prepared_statements: false     # wajib di belakang pooler
    advisory_locks: false          # migrasi lewat pooler akan menggantung tanpa ini
```

> Jalankan migrasi memakai koneksi **direct** (5432), lalu biarkan runtime memakai
> pooler. Kalau migrasi tetap lewat pooler, `advisory_locks: false` mencegah hang
> tapi Anda kehilangan proteksi migrasi paralel — jangan pernah jalankan dua
> migrasi bersamaan.

### 1.3 Multi-database Rails 8

Default Rails 8 memberi `solid_queue`, `solid_cache`, dan `solid_cable` masing-masing
database sendiri. Supabase free memberi Anda **satu** database.

Dua jalan keluar, pilih satu:

**A. Satukan ke satu database (paling sederhana).** Solid Queue jalan baik dalam
database yang sama dengan primary. Arahkan semuanya ke satu `DATABASE_URL` dan
buang `solid_cache`/`solid_cable` kalau tidak dipakai.

**B. Pisahkan per schema.** Satu database Postgres, schema berbeda
(`public`, `queue`). Lebih rapi, tapi tambah kerumitan yang belum tentu Anda butuh
sekarang.

Saya sarankan **A** sampai ada alasan konkret untuk pindah.

### 1.4 Pindahkan data yang sudah ada

Riwayat forward tracking Anda adalah aset yang tidak bisa dibuat ulang. Pindahkan
sebelum apa pun yang lain, dan simpan dump-nya di luar kedua sistem.

```bash
pg_dump --no-owner --no-privileges "$OLD_DATABASE_URL" > idx-backup-$(date +%F).sql
psql "$SUPABASE_DIRECT_URL" < idx-backup-$(date +%F).sql

# Verifikasi jumlah baris cocok, jangan percaya "selesai tanpa error"
psql "$SUPABASE_DIRECT_URL" -c "\dt"
psql "$SUPABASE_DIRECT_URL" -c "SELECT count(*) FROM <tabel_forward_tracking>;"
```

---

## Fase 2 — GitHub Actions (job harian)

### 2.1 Satukan pekerjaan harian jadi satu perintah

Ini yang membuat penjadwalnya bisa ditukar nanti. Satu entry point, bukan lima.

```ruby
# lib/tasks/idx.rake
namespace :idx do
  desc "Seluruh pekerjaan harian: forward tracking, backup bukti, alert"
  task daily: :environment do
    # GANTI dengan nama kelas/task Anda yang sebenarnya — ini placeholder.
    # Ambil dari config/recurring.yml hasil Fase 0.
    ForwardTracker.run!
    EvidenceBackup.rotate!
  end
end
```

Uji lokal dulu melawan Supabase sebelum menyentuh CI:

```bash
DATABASE_URL="$SUPABASE_DIRECT_URL" RAILS_ENV=production bundle exec rake idx:daily
```

### 2.2 Konversi jam — WIB ke UTC

**Cron GitHub Actions memakai UTC.** WIB = UTC+7 dan tidak punya DST, jadi
konversinya tetap: **kurangi 7 jam.**

| Mau jalan (WIB) | Tulis di cron (UTC) |
|---|---|
| 06:00 | `0 23 * * *` ← hari sebelumnya |
| 17:30 | `30 10 * * *` |
| 18:00 | `0 11 * * *` |

IDX tutup 16:00 WIB dan pre-closing selesai ~16:15. Menjalankan **17:30 WIB
(`30 10 * * *`)** memberi jeda aman agar data penutupan sudah tersedia.

### 2.3 Workflow

`.github/workflows/daily.yml`

```yaml
name: Daily forward tracking

on:
  schedule:
    - cron: '30 10 * * *'   # 17:30 WIB — lihat tabel konversi di atas
  workflow_dispatch:         # tombol manual, wajib ada untuk menguji

# Jangan pernah biarkan dua run bertumpuk menulis ke database yang sama.
concurrency:
  group: idx-daily
  cancel-in-progress: false

jobs:
  daily:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    env:
      RAILS_ENV: production
      DATABASE_URL: ${{ secrets.DATABASE_URL }}
      RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
      TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
      TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true    # baca .ruby-version, cache gem otomatis

      - name: Jalankan pekerjaan harian
        run: bundle exec rake idx:daily

      # Ping HANYA setelah rake sukses. Ping tanpa syarat berarti dead man's
      # switch Anda melaporkan sehat padahal jobnya gagal.
      - name: Lapor sukses
        if: success()
        run: curl -fsS -m 10 --retry 3 "${{ secrets.HEALTHCHECK_URL }}"

      - name: Lapor gagal
        if: failure()
        run: curl -fsS -m 10 --retry 3 "${{ secrets.HEALTHCHECK_URL }}/fail"
```

### 2.4 Secrets

Settings → Secrets and variables → Actions:

| Secret | Isi |
|---|---|
| `DATABASE_URL` | Supabase **pooler** (6543) |
| `RAILS_MASTER_KEY` | isi `config/master.key` |
| `TELEGRAM_BOT_TOKEN` | punya Anda |
| `TELEGRAM_CHAT_ID` | punya Anda |
| `HEALTHCHECK_URL` | dari Fase 4 |

> Repo ini publik. Secrets tidak terbaca dari fork dan tidak muncul di log, **tapi
> `workflow_dispatch` bisa dijalankan siapa pun yang punya write access.** Pastikan
> daftar kolaborator repo memang yang Anda maksud.

---

## Fase 3 — Koyeb (web dashboard, opsional/tidak dipakai sekarang)

> **Skip fase ini** untuk dashboard portofolio — sudah digantikan Fase 3.5
> (frontend statis di Vercel), yang tidak butuh server Ruby hidup sama sekali.
> Bagian di bawah ini relevan lagi kalau nanti Anda benar-benar butuh fitur
> interaktif (search simbol bebas live, upload ticker lewat web, dll).

> Render dan Fly.io sama-sama mewajibkan kartu kredit untuk verifikasi akun.
> Koyeb (per pengetahuan saya) masih menawarkan free tier tanpa kartu — **cek
> langsung saat daftar**, kebijakan begini berubah cukup sering. `Dockerfile`,
> `bin/docker-entrypoint`, `.dockerignore` yang sudah dibuat generik, jadi
> dipakai apa adanya (tidak ada bagian khusus Fly.io di dalamnya).

Kalau Koyeb ternyata juga mulai minta kartu saat Anda coba, jalur yang tersisa
untuk tetap punya fitur interaktif (search dkk) tanpa kartu sama sekali adalah
self-host + Cloudflare Tunnel di komputer yang menyala terus — beri tahu saya
kalau situasinya berubah, saya siapkan itu.

### 3.1 Setup awal (sekali saja, lewat Koyeb CLI)

```bash
# install koyeb CLI, lalu:
koyeb login

koyeb secrets create database-url --value "$SUPABASE_POOLER_URL"
koyeb secrets create rails-master-key --value "$(cat config/master.key)"
koyeb secrets create telegram-bot-token --value "..."
koyeb secrets create telegram-chat-id --value "..."

koyeb app init idx-screener

koyeb service create web \
  --app idx-screener \
  --git github.com/dvdadriel/idx-screener \
  --git-branch main \
  --git-builder docker \
  --instance-type free \
  --regions sin \
  --ports 80:http \
  --routes /:80 \
  --checks 80:http:/up \
  --env RAILS_ENV=production \
  --env RAILS_SERVE_STATIC_FILES=true \
  --env DATABASE_URL=@database-url \
  --env RAILS_MASTER_KEY=@rails-master-key \
  --env TELEGRAM_BOT_TOKEN=@telegram-bot-token \
  --env TELEGRAM_CHAT_ID=@telegram-chat-id
```

### 3.2 Migrasi

**Jangan** lewat `bin/docker-entrypoint` otomatis — `DATABASE_URL` di secrets
adalah pooler (6543), tidak mendukung DDL. Migrasi dari lokal lewat direct URL:

```bash
DATABASE_URL="$SUPABASE_DIRECT_URL" RAILS_ENV=production bin/rails db:prepare
```

### 3.3 Subdomain

- Koyeb → service → Settings → Domains → tambah `idx.domain-anda.com`
- DNS: CNAME `idx` → host yang Koyeb berikan
- Sertifikat otomatis; tunggu propagasi sebelum menguji

### 3.4 Tier gratis akan tidur

Instance free Koyeb tidur setelah tidak aktif; pengunjung pertama menunggu
cold start. Ini tidak mempengaruhi job harian (jalan di GitHub Actions), hanya
pengalaman orang yang mengklik tautan.

Kalau tautan ini akan Anda tunjukkan ke recruiter, pertimbangkan Fase 6.

### 3.5 Frontend statis (React) di Vercel

Dashboard read-only sekarang ada di `frontend/` (lihat
docs/superpowers/specs/2026-08-28-static-portfolio-dashboard-design.md).
Deploy terpisah dari Rails:

1. Vercel → New Project → import repo, **Root Directory** = `frontend`
2. Framework preset: Vite (auto-detected dari `vercel.json`)
3. Environment variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
   (anon key publik Supabase — aman diexpose, itu tujuannya, dibatasi RLS)
4. Deploy — Vercel kasih URL `*.vercel.app`, tambahkan custom domain kalau mau

---

## Fase 4 — Dead man's switch

Watchdog di dalam sistem tidak bisa melaporkan bahwa sistemnya tidak jalan. Ini yang
menutup celah itu.

1. Daftar di **healthchecks.io** (gratis), buat check baru
2. **Period** 1 hari, **Grace** 2 jam
3. Ambil ping URL → simpan sebagai secret `HEALTHCHECK_URL`
4. Integrasi → **Telegram**, arahkan ke chat yang sama dengan alert IdxScreener

Sekarang Anda mendapat kabar untuk tiga mode kegagalan yang tidak terdeteksi sendiri:

- Rake task error → step `failure()` ping `/fail`
- GitHub mematikan schedule karena repo 60 hari tanpa aktivitas → ping tidak datang
- Runner tidak pernah jalan sama sekali → ping tidak datang

---

## Fase 5 — Verifikasi

Jangan anggap selesai sebelum kelimanya lulus. Nomor 5 yang paling sering dilewatkan
dan justru paling penting.

```
[ ] 1. workflow_dispatch manual → run hijau
[ ] 2. Baris baru benar-benar masuk Supabase pada tanggal hari ini
       psql "$SUPABASE_DIRECT_URL" -c "SELECT max(created_at) FROM <tabel>;"
[ ] 3. healthchecks.io berubah jadi "up" setelah run itu
[ ] 4. Dashboard Render menampilkan baris baru tersebut
[ ] 5. Sengaja rusakkan: ubah rake task agar raise, jalankan manual,
       pastikan Telegram benar-benar berbunyi. Lalu kembalikan.
[ ] 6. Besoknya: cek run terjadwal jalan sendiri tanpa disentuh
```

---

## Fase 6 — Opsional: snapshot statis

Menyelesaikan masalah cold start tanpa biaya. Dashboard Anda isinya laporan harian —
halaman seperti itu tidak butuh server hidup.

Tambahkan step di akhir workflow harian: render hasil terakhir jadi HTML/JSON statis,
publikasikan ke Cloudflare Pages. Tautan di portfolio mengarah ke situ — langsung
terbuka, nol cold start, nol biaya. Rails hanya dibutuhkan untuk bagian interaktif.

Kalau Anda ambil jalur ini, web service Render boleh tetap gratis selamanya.

---

## Jebakan — ringkasan

| Jebakan | Akibat kalau terlewat | Penangkal |
|---|---|---|
| Pooler tanpa `prepared_statements: false` | Error `prepared statement already exists` yang menyesatkan | Fase 1.2 |
| Migrasi lewat pooler | Perintah menggantung tanpa pesan | Migrasi via port 5432 |
| Cron ditulis dalam WIB | Job jalan 7 jam lebih awal | Tabel konversi Fase 2.2 |
| Jadwal harian tertinggal di `recurring.yml` | Job jalan dua kali, data ganda | Fase 3.2 |
| Ping healthcheck tanpa `if: success()` | Sistem melapor sehat padahal gagal | Fase 2.3 |
| Multi-DB Rails 8 vs satu DB Supabase | Deploy gagal saat boot | Fase 1.3 |
| Schedule mati setelah 60 hari repo sepi | Riwayat berhenti bertambah dalam diam | Fase 4 |
| Data lama belum dipindah | Riwayat forward tracking hilang permanen | Fase 1.4, kerjakan paling awal |

---

## Catatan kejujuran

- Nama kelas `ForwardTracker` dan `EvidenceBackup` adalah **placeholder**. Ganti
  dengan yang sebenarnya, dari hasil Fase 0.
- Syarat dan batas tier gratis Supabase, Render, dan GitHub berubah cukup sering, dan
  pengetahuan saya ada batas waktunya. Cek angka terkininya sendiri. Bentuk
  arsitekturnya tidak berubah oleh itu.
- Urutan fase itu sengaja: **Fase 1.4 (pindah data) sebelum apa pun yang lain.**
  Sisanya bisa dicoba ulang; data yang hilang tidak.
