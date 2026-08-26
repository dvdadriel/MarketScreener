# Hasil Backtest

**Dijalankan:** 2026-08-26
**Universe:** 223 simbol saham IDX (`EXTENDED_WATCHLIST`, ≈KOMPAS100), benchmark `^JKSE`
**Strategi:** cross-sectional momentum, rebalance bulanan, top-10
**Biaya:** fee 0,4% round-trip (khas IDX)

Semua angka di bawah adalah hasil **backtest dan paper trading**, bukan eksekusi dengan uang sungguhan. Baca [bagian batasan](#batasan--baca-bagian-ini) sebelum menyimpulkan apa pun.

## Walk-forward: jendela × buffer zone

`buffer` menahan posisi sampai keluar dari peringkat top-N yang lebih longgar, untuk menekan turnover. `off` berarti rebalance ketat ke top-10 tiap bulan.

| Window | Buffer | Return | Alpha vs IHSG | Max DD | Sharpe |
|---|---|---|---|---|---|
| 365d | off | −3,98% | +16,31% | 11,85% | −0,03 |
| 365d | 12 | +0,42% | +20,71% | 8,61% | 0,45 |
| 365d | 15 | +1,44% | +21,73% | 9,35% | 0,55 |
| 365d | 20 | +1,44% | +21,73% | 9,35% | 0,55 |
| 730d | off | +0,66% | +16,39% | 12,40% | 0,39 |
| 730d | 12 | +4,47% | +20,20% | 12,40% | 0,54 |
| 730d | 15 | +7,09% | +22,82% | 10,90% | 0,65 |
| 730d | 20 | **+8,92%** | **+24,65%** | 10,95% | **0,73** |
| 1095d | off | −15,82% | −5,20% | 15,97% | −0,32 |
| 1095d | 12 | −16,44% | −5,82% | 16,66% | −0,37 |
| 1095d | 15 | −12,80% | −2,18% | 14,50% | −0,23 |
| 1095d | 20 | −2,06% | +8,56% | 11,22% | 0,26 |

Reproduksi: `bin/rails 'momentum:buffer_sweep[extended]'`

### Cara membaca tabel ini

**Return absolutnya lemah; alpha-nya yang menarik.** Di jendela 365 dan 730 hari, return absolut berkisar −4% sampai +9% — tidak mengesankan. Tapi alpha terhadap IHSG **+16% sampai +25%**, karena IHSG turun lebih dalam pada periode yang sama. Artinya kontribusi utamanya adalah **menghindari kerugian**, bukan mengejar keuntungan — konsisten dengan gate regime yang menahan portofolio ke cash saat pasar risk-off.

**Jendela 1095 hari rugi di hampir semua konfigurasi.** Ini jendela terpanjang dan paling dekat dengan batas ketersediaan data (lihat batasan), jadi paling sedikit bisa diandalkan — tapi tetap dicantumkan karena menghilangkannya berarti memilih jendela yang menguntungkan.

**Buffer zone konsisten membantu, dan sensitivitasnya mencurigakan.** Di ketiga jendela, buffer memperbaiki return dan Sharpe sekaligus menurunkan drawdown. Tapi di jendela 1095d, selisih buffer 15 → 20 mengubah return dari −12,80% ke −2,06% — 10,7 poin persentase hanya dari menggeser satu parameter. Sensitivitas sebesar itu adalah tanda **overfitting**, bukan tanda penemuan. Buffer 20 memberi angka terbaik di dua dari tiga jendela, dan justru karena itu ia patut dicurigai, bukan dipilih.

## Forward tracking (paper, uang tidak sungguhan)

```
Forward tracking: 2026-07-16 → 2026-08-24 (21 hari-snapshot)
Equity paper: 100.00 (+0.00%)  maxDD: -0.00%  |  IHSG: 4.42%
Alpha vs IHSG: -4.42%  |  Regime hari ini: risk_off
Holdings: CASH
```

Reproduksi: `bin/rails momentum:paper`

**Ini hasil yang tidak menyenangkan, dan justru yang paling informatif.** Sejak inception, gate regime menahan portofolio **100% di cash selama seluruh 21 hari-snapshot**, sementara IHSG naik 4,42%. Jadi alpha forward-nya **−4,42%**.

Backtest bilang gate regime menyelamatkan dari penurunan. Forward tracking bilang gate yang sama membuat ketinggalan kenaikan. Keduanya konsisten dengan satu penjelasan: gate ini **mengurangi eksposur, bukan meningkatkan seleksi** — dan apakah itu bagus sepenuhnya tergantung arah pasar berikutnya, yang tidak diketahui.

21 hari-snapshot terlalu pendek untuk menyimpulkan apa pun. Gate promosi strategi ini butuh 8 minggu; sampai itu tercapai, strategi tetap dalam observasi dan alert-nya di-mute.

## Batasan — baca bagian ini

### Reproducibility: run pertama memberi angka yang salah

Backtest mengambil histori candle yang kurang secara **on-demand**, tanpa peringatan. Run pertama pada 2026-08-26 memberi **−6,78%** untuk 365d/buffer-15. Run berikutnya, dengan parameter identik, memberi **+1,44%** — dan stabil di angka itu pada dua run berikutnya lagi.

Penyebabnya cache candle yang tumbuh selama proses:

| | Run pertama | Setelah cache hangat |
|---|---|---|
| Candle saham | 517.066 | 705.717 (+36%) |
| Candle indeks | 701 | 1.199 (+71%) |

**Selisih 8,2 poin persentase, tanpa satu pun peringatan.** Guard `check_coverage!` dengan `MAX_MISSING_SHARE = 0.10` tidak menyala, artinya coverage saat itu masih di atas 90% — tapi 10% data hilang ternyata cukup untuk menggeser hasil sebesar itu. **Toleransi 10% itu terlalu longgar** dan seharusnya diperketat.

Semua angka di dokumen ini diambil dari cache hangat dan diverifikasi reproducible.

### Batasan lain

- **Sampel pendek.** Data indeks hanya ≈1.199 candle harian (≈4,8 tahun bursa) dan jendela 1095 hari sudah menyentuh batas itu. Belum melewati satu siklus pasar penuh.
- **Survivorship bias.** Universe dibentuk dari saham yang masih listing hari ini, jadi emiten yang sudah delisting tidak ikut terhitung. Ini membuat hasil backtest **lebih baik** dari kenyataan.
- **Gate regime di-bypass saat backtest.** Rake task `backtest:run` menyatakannya sendiri di outputnya. Jadi angka backtest dan perilaku forward tracking tidak sepenuhnya mengukur hal yang sama.
- **Fee dan slippage adalah estimasi**, bukan hasil fill sebenarnya. Tidak ada model market impact.
- **Tidak ada koreksi multiple-testing.** Tabel di atas memuat 12 kombinasi. Memilih yang terbaik dari 12 percobaan lalu melaporkannya sebagai temuan adalah kekeliruan statistik; itu sebabnya bagian di atas menyoroti sensitivitas parameter alih-alih menonjolkan angka terbaik.
- **Belum pernah dieksekusi dengan uang sungguhan.**

## Paper trading per strategi — di sini letak masalahnya

Diambil dari tabel `paper_trades`, seluruh trade yang sudah ditutup: **16.879 trade, 2026-05-26 → 2026-08-26** (3 bulan).

### Agregat

| Metrik | Nilai |
|---|---|
| Trade closed | 16.879 |
| Win / loss | 1.309 / 15.570 |
| Win rate | **7,76%** |
| Avg P&L per trade | **−0,196%** |
| Profit factor | **0,784** (gain 12.026,9 / loss 15.335,9) |

Profit factor di bawah 1 berarti total kerugian melebihi total keuntungan. Ini bukan hasil yang bagus, dan tidak ada gunanya dibungkus.

### Per strategi

| Strategi | n | Win rate | Avg P&L | Sum P&L |
|---|---|---|---|---|
| `CONFLUENCE_BEARISH` | 13.481 | 0,6% | +0,00% | +25,8 |
| `CONFLUENCE_BULLISH` | 2.956 | 35,4% | −1,00% | **−2.957,5** |
| `SWING_PICK` | 270 | 40,0% | −0,38% | −102,4 |
| `MACD_BULLISH` | 38 | 28,9% | −3,99% | −151,6 |
| `MACD_BEARISH` | 33 | 54,5% | −2,52% | −83,1 |
| `SQUEEZE_BREAKOUT` | 27 | 18,5% | −1,03% | −27,8 |
| `BB_BREAKOUT_UPPER` | 26 | 88,5% | +1,28% | +33,3 |
| `RSI_OVERSOLD` | 16 | 18,8% | −2,86% | −45,7 |
| `VOLUME_SPIKE` | 8 | 50,0% | −0,13% | −1,0 |
| `RSI_OVERBOUGHT` | 8 | 50,0% | +0,27% | +2,2 |
| `BB_BREAKOUT_LOWER` | 7 | 0,0% | −1,24% | −8,7 |
| `RSI_FAST_OVERSOLD` | 4 | 50,0% | +0,52% | +2,1 |
| `RSI_FAST_OVERBOUGHT` | 4 | 0,0% | −1,38% | −5,5 |
| `MACD_BULL_CROSS` | 1 | 100,0% | +11,02% | +11,0 |

### Tiga temuan dari tabel ini

**1. Satu strategi menyumbang hampir seluruh kerugian.** `CONFLUENCE_BULLISH` menghasilkan −2.957,5 dari total −3.309 — sekitar **89% dari seluruh kerugian berasal dari satu strategi**. Menonaktifkannya, bukan menyetel yang lain, adalah tindakan dengan dampak terbesar.

**2. `CONFLUENCE_BEARISH` adalah pembangkit sinyal degenerat, bukan strategi.** n = 13.481 — **80% dari seluruh trade** — dengan win rate **0,6%** dan avg P&L +0,00%. Sesuatu yang menghasilkan tiga belas ribu sinyal dan hampir tidak pernah menang bukan strategi yang berkinerja buruk; ia rusak. Volumenya juga membuat statistik agregat tidak bermakna: win rate keseluruhan 7,76% hampir seluruhnya cerminan strategi ini.

**3. Strategi dengan angka terbaik justru yang sampelnya terkecil.** `BB_BREAKOUT_UPPER` (WR 88,5%, avg +1,28%) hanya n=26. `MACD_BULL_CROSS` menunjukkan +11,02% dari **satu** trade. Angka-angka itu tidak berarti apa pun, dan mencantumkannya sebagai keberhasilan akan menyesatkan.

## Strategi yang gagal

- **`SQUEEZE_BREAKOUT`** — win rate 18,5%, avg −1,03% dari 27 trade. Membenarkan keputusan membatasinya hanya untuk crypto dan tidak memakainya untuk saham.
- **`CONFLUENCE_BULLISH`** — sumber 89% kerugian (di atas). `SignalConfluenceService` memang masih paper baseline dengan alert **di-mute**; data ini menjelaskan kenapa itu keputusan yang tepat.
- **`CONFLUENCE_BEARISH`** — rusak, bukan sekadar merugi (di atas).
- **`RSI_OVERSOLD`** — win rate 18,8%, avg −2,86%. Sampel kecil (n=16) tapi arahnya konsisten dengan `RSI_FAST_OVERSOLD`.

## Bug yang ditemukan saat menyusun dokumen ini

**Max drawdown pada dashboard salah hitung.** Dashboard menampilkan `Max Drawdown -4152.12%`. Drawdown ekuitas secara matematis tidak mungkin melewati −100%. Angka itu berasal dari **penjumlahan `pnl_pct` per trade** (sum = −3.309, dan tumbuh seiring trade baru ditutup), bukan dari peak-to-trough kurva ekuitas yang di-compound. Belum diperbaiki; dicatat di sini supaya angka di dashboard tidak dipercaya sebagai drawdown.

## Kesimpulan yang jujur

Sistem ini berhasil melakukan apa yang seharusnya dilakukan sistem pengukuran: **memberi tahu bahwa strateginya belum terbukti bekerja, dan menunjukkan di mana persoalannya.**

Yang bisa dikatakan dengan data ini: strategi cross-sectional momentum dengan gate regime mengurangi drawdown dan mengalahkan IHSG secara relatif di jendela 1–2 tahun, terutama dengan **menghindari eksposur** saat risk-off — bukan dengan memilih saham lebih baik.

Yang **tidak** bisa dikatakan: bahwa sistem ini menghasilkan uang. Bukti yang bertentangan lebih banyak daripada yang mendukung:

- Return absolut backtest tipis (−4% s/d +9%), dan jendela terpanjang rugi
- Sensitivitas parameter mengkhawatirkan (buffer 15 → 20 menggeser 10,7 poin persentase)
- Forward tracking nol selama 21 hari sementara IHSG naik
- Paper trading profit factor **0,784** — kerugian melebihi keuntungan
- Satu strategi (`CONFLUENCE_BULLISH`) menyumbang 89% kerugian
- Satu lagi (`CONFLUENCE_BEARISH`) rusak dan mendominasi 80% volume trade
- Run pertama backtest memberi angka yang salah tanpa peringatan

Tindakan berikutnya yang jelas dari data ini, berurutan: **matikan `CONFLUENCE_BULLISH`**, **perbaiki atau hapus `CONFLUENCE_BEARISH`**, **perketat `MAX_MISSING_SHARE`**, dan **perbaiki perhitungan max drawdown**. Baru setelah itu angka agregatnya layak dibaca lagi.

Strategi tetap dalam observasi. Tidak ada uang sungguhan yang pernah dipertaruhkan di sini, dan berdasarkan data di atas, itu keputusan yang benar.
