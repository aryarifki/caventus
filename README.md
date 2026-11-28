# Caventus — Pixel 6 (`oriole`) KernelSU RAM Optimizer + Material 3 Expressive WebUI

Modul **KernelSU** (*overlay-free*, tanpa modifikasi `/system` atau `/vendor`) yang dioptimalkan khusus untuk **Google Pixel 6 (`oriole` / Tensor GS101, 8 GB RAM)**, dilengkapi **KernelSU WebUI** bergaya **Material 3 Expressive** (terinspirasi dari [`dpejoh/specter`](https://github.com/dpejoh/specter)), **ART `speed-profile` recompile (`-f`)**, serta **Forensic Diagnostic Log Capture (`caventus-diag.sh`)** untuk merekam dan mengekspor telemetri lengkap (boot trace, `logcat`, `dmesg`, thermal, PSI, CPUFreq, zRAM/vmstat, LMKD) ke `/sdcard/Download/Caventus-Logs/`.

---

## Pembaruan CI `v1.4.3-ci` (Always-On Realtime Forensic Logger — Build CI)

> **Catatan:** `v1.4.3-ci` adalah build **khusus CI** (`ci/v1.4.3-realtime-logger`, belum dirilis ke GitHub Releases publik) untuk pengumpulan log multi-jam.

1. **Daemon Logger 24/7 Anti-LMKD (`/data/adb/caventus/realtime/`):** Berjalan otomatis pasca-boot via `setsid`, `oom_score_adj=-900`, `renice +5` sehingga tidak ikut ter-kill saat membuka banyak aplikasi berat dan tetap merekam meski WebUI ditutup.
2. **Telemetry Berputar Otomatis (`max 15 MB`):**
   - `metrics.tsv`: time-series tiap `10s` (`mem_avail`, `swap_used`, `zram_mem`, `bd_stat`, delta `pswpin`/`pswpout`/`pgmajfault`/`allocstall`/`oom`, PSI, thermal `BIG`/`MID`/`battery`, cooling throttle, clock MHz, flags).
   - `anomalies.log`: snapshot lengkap (`top`, `ps`, `dumpsys meminfo --short`, PSI, `sda_ra`/`mglru_ttl` drift) tiap kali terdeteksi `THERMAL`, `LOWMEM`, `SWAPFULL`, `THRASH`, `PSI_MEM`, `PSI_IO`, `ALLOCSTALL`, atau `OOM`, plus checkpoint tiap `10 menit`.
   - `events.log`: delta event `dmesg` & `logcat` tiap `60s`.
   - `session.meta` & `daemon.status`: metadata boot + status daemon live.
3. **Ekspor 1-Tap Multi-Jam:** Buka WebUI → **Ekspor Log Realtime (Multi-Jam)** (atau `caventus-ctl.sh diag-daemon-export`) untuk menggabungkan seluruh sesi ke `/sdcard/Download/Caventus-Logs/latest-caventus-realtime.log` (dan arsip `.tar.gz`).

---

## Pembaruan Utama `v1.4.2` (6 GB `lz77eh`, Auto-Migration, Balanced LMKD & Thermal Guard)

1. **Auto-Migrasi `config.env` Schema (`v1` → `v2`):** Config lama dari `v1.4.0`/`v1.4.1` (`4096`/`5120 MB` & LMKD lama) otomatis dimigrasi saat `apply` pertama kali sehingga tidak lagi menimpa `mmd.zram.size` dengan ukuran usang (tetap menghormati angka custom pengguna).
2. **zRAM Default Naik ke `6144 MB` (6 GB) `lz77eh`:** Rasio hardware GS101 `~2.93×` memberi +1 GB headroom swap dengan biaya RAM fisik hanya ~230 MB untuk meredam `pgmajfault` thrashing.
3. **Kalibrasi LMKD PSI Balanced-Responsive (`70/500/50/15%/90%`):** Membersihkan aplikasi background secara progresif sebelum `SwapFree` habis tanpa memicu badai kill.
4. **Thermal & Uptime Guard pada ART Recompile (`caventus-ctl.sh recompile`):** Menahan kompilasi `speed-profile` bila `uptime < 120s` atau suhu SoC `>= 70°C` (kecuali `--force`) serta cooldown otomatis tiap 15 paket jika SoC `>= 78°C`.
5. **Diagnostik `caventus-diag.sh` Diperkuat:** Menambah `dumpsys meminfo --short` di Section 09, logging `rc=` + `logcat -g` probe di Section 11, dan multi-fallback `/system/bin/dmesg` → `toybox dmesg` → `busybox dmesg` di Section 12.

---

## Pembaruan Utama `v1.4.1` (Hotfix 32-bit `mksh`, 5 GB `lz77eh`, Nav Indicator Fix)

1. **Hotfix Overflow 32-bit `mksh` Android:** Seluruh konversi MB↔byte zRAM (`mb_to_bytes`/`bytes_to_mb`) & `ZRAM_FULL_PCT` kini memakai `awk` 64-bit agar ukuran >= 4 GB (`5368709120`) tidak lagi overflow menjadi `0` di `/system/bin/sh` Android.
2. **zRAM Default Naik ke `5120 MB` (5 GB) `lz77eh`:** Berdasarkan log perangkat nyata (`4 GB` penuh 99.98% dalam 4 menit pada rasio hardware `3.15x`), `5 GB` memberi headroom ekstra untuk meredam `pgmajfault` saat membuka aplikasi berat.
3. **Logcat/dmesg & Section 13 Clean Count:** Memakai `/system/bin/logcat -b main -b system -b events -b crash`, `/system/bin/dmesg`, dan `count_matches()` yang bersih tanpa output ganda `0\n0`.
4. **WebUI Nav Indicator Alignment:** Indikator pil bawah memakai `getBoundingClientRect()` + `translate3d` + frame tracking & `ResizeObserver` sehingga selalu sejajar saat pindah tab atau ganti bahasa.
5. **Anti-`odrefresh`, Anti-`swapoff` Freeze & GS101 Thermal-Safe Default:** `ART_BOOT_PROPS=0`, `ZRAM_RUNTIME_RESIZE=0`, `SCHED_PROFILE=stock`, `CPU_RATE_PROFILE=stock`, dan LMKD PSI longgar (`70/700/80/10%/95%`).

---

## Profil Default Otomatis `v1.4.2` (*Oriole Safe & Cool*)

| Komponen | Nilai Default (`v1.4.2`) | Keterangan |
| :--- | :--- | :--- |
| **zRAM + `mmd`** | **`6144 MB` (`6442450944` B)**, `lz77eh`, `mmd_sync=1`, `runtime_resize=0` | Hardware Emerald Hill GS101 + auto-migrasi schema v2 tanpa `swapoff` freeze pasca-boot. |
| **ART / `dex2oat`** | `pm.dexopt=speed-profile`, `madvise=64 MB`, `ART_BOOT_PROPS=0` | Tanpa memicu `odrefresh` saat boot + Thermal/Uptime Guard pada `recompile`. |
| **LMKD (PSI)** | `partial=70ms`, `complete=500ms`, `thrashing=50`, `swap_low=15%`, `swap_util=90%` | Balanced-responsive: menjaga cache & melepas app berat sebelum zRAM jenuh. |
| **Kernel VM & MGLRU** | `swappiness=70`, `watermark_scale=55`, `dirty=10/20`, `MGLRU=1 (0x0003)`, `THP=never` | Seimbang dan hemat RAM tanpa memicu direct reclaim / thermal tinggi. |
| **GS101 Sched & CPUFreq** | `SCHED_PROFILE=stock`, `CPU_RATE_PROFILE=stock` | Bebas panas berlebih; profil `balanced`/`responsive` tetap tersedia opt-in. |
| **UFS 3.1 & Mali** | `mq-deadline`, `read_ahead=256 KB`, `nr_requests=128`, `async_depth=64`, `adaptive` | `iostats` dipertahankan aktif untuk analisis diagnostik. |
| **SurfaceFlinger** | `off` | Tidak mengubah properti Composer HAL saat boot. |

---

## Cara Mengambil & Mengirim Log Diagnostik Lengkap

1. Flash **`caventus-oriole-v1.4.2.zip`** di **KernelSU Manager** → **Modules** → **Install**, lalu **Reboot**.
2. Buka **KernelSU Manager** → tap **WebUI** pada Caventus → buka tab **Tools** (atau tap *Tangkap Log Diagnostik (15s)* di **Home**).
3. Pilih durasi (**Instan 0s**, **Normal 15s**, atau **Uji Buka App 30s** sambil membuka aplikasi yang terasa lambat) → tap **Rekam & Ekspor Log Lengkap**.
4. File laporan lengkap tersimpan di **`/sdcard/Download/Caventus-Logs/latest-caventus-diag.log`** dan bisa langsung dilihat/disalin dari modal WebUI.

---

## Pemulihan Tanpa PC (*KernelSU Safe Mode*)

Jika terjadi kendala boot: tahan tombol **Power ±10–15 detik** hingga restart, lalu begitu logo **Google** muncul **tekan-lepas tombol Volume Down berulang (>3 kali)** untuk masuk ke **KernelSU Safe Mode** (menonaktifkan semua modul).

---

## Build & Verifikasi Lokal

```bash
python3 scripts/build_zip.py
python3 scripts/verify_module.py
```
