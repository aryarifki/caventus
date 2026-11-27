# Caventus — Pixel 6 (`oriole`) KernelSU RAM Optimizer + Material 3 Expressive WebUI

Modul **KernelSU** (*overlay-free*, tanpa modifikasi `/system` atau `/vendor`) yang dioptimalkan khusus untuk **Google Pixel 6 (`oriole` / Tensor GS101, 8 GB RAM)**, dilengkapi **KernelSU WebUI** bergaya **Material 3 Expressive** (terinspirasi dari [`dpejoh/specter`](https://github.com/dpejoh/specter)), **ART `speed-profile` recompile (`-f`)**, serta **Forensic Diagnostic Log Capture (`caventus-diag.sh`)** untuk merekam dan mengekspor telemetri lengkap (boot trace, `logcat`, `dmesg`, thermal, PSI, CPUFreq, zRAM/vmstat, LMKD) ke `/sdcard/Download/Caventus-Logs/`.

---

## Pembaruan Utama `v1.4.1` (Hotfix 32-bit `mksh`, 5 GB `lz77eh`, Nav Indicator Fix)

1. **Hotfix Overflow 32-bit `mksh` Android:** Seluruh konversi MB↔byte zRAM (`mb_to_bytes`/`bytes_to_mb`) & `ZRAM_FULL_PCT` kini memakai `awk` 64-bit agar ukuran >= 4 GB (`5368709120`) tidak lagi overflow menjadi `0` di `/system/bin/sh` Android.
2. **zRAM Default Naik ke `5120 MB` (5 GB) `lz77eh`:** Berdasarkan log perangkat nyata (`4 GB` penuh 99.98% dalam 4 menit pada rasio hardware `3.15x`), `5 GB` memberi headroom ekstra untuk meredam `pgmajfault` saat membuka aplikasi berat.
3. **Logcat/dmesg & Section 13 Clean Count:** Memakai `/system/bin/logcat -b main -b system -b events -b crash`, `/system/bin/dmesg`, dan `count_matches()` yang bersih tanpa output ganda `0\n0`.
4. **WebUI Nav Indicator Alignment:** Indikator pil bawah memakai `getBoundingClientRect()` + `translate3d` + frame tracking & `ResizeObserver` sehingga selalu sejajar saat pindah tab atau ganti bahasa.
5. **Anti-`odrefresh`, Anti-`swapoff` Freeze & GS101 Thermal-Safe Default:** `ART_BOOT_PROPS=0`, `ZRAM_RUNTIME_RESIZE=0`, `SCHED_PROFILE=stock`, `CPU_RATE_PROFILE=stock`, dan LMKD PSI longgar (`70/700/80/10%/95%`).

---

## Profil Default Otomatis `v1.4.1` (*Oriole Safe & Cool*)

| Komponen | Nilai Default (`v1.4.1`) | Keterangan |
| :--- | :--- | :--- |
| **zRAM + `mmd`** | **`5120 MB` (`5368709120` B)**, `lz77eh`, `mmd_sync=1`, `runtime_resize=0` | Hardware Emerald Hill GS101 tanpa overflow 32-bit dan tanpa `swapoff` freeze pasca-boot. |
| **ART / `dex2oat`** | `pm.dexopt=speed-profile`, `madvise=64 MB`, `ART_BOOT_PROPS=0` | Tanpa memicu `odrefresh` saat boot. |
| **LMKD (PSI)** | `partial=70ms`, `complete=700ms`, `thrashing=80`, `swap_low=10%`, `swap_util=95%` | Menghindari kill berulang yang membuat app lambat dibuka. |
| **Kernel VM & MGLRU** | `swappiness=70`, `watermark_scale=55`, `dirty=10/20`, `MGLRU=1 (0x0003)`, `THP=never` | Seimbang dan hemat RAM tanpa memicu direct reclaim / thermal tinggi. |
| **GS101 Sched & CPUFreq** | `SCHED_PROFILE=stock`, `CPU_RATE_PROFILE=stock` | Bebas panas berlebih; profil `balanced`/`responsive` tetap tersedia opt-in. |
| **UFS 3.1 & Mali** | `mq-deadline`, `read_ahead=256 KB`, `nr_requests=128`, `async_depth=64`, `adaptive` | `iostats` dipertahankan aktif untuk analisis diagnostik. |
| **SurfaceFlinger** | `off` | Tidak mengubah properti Composer HAL saat boot. |

---

## Cara Mengambil & Mengirim Log Diagnostik Lengkap

1. Flash **`caventus-oriole-v1.4.1.zip`** di **KernelSU Manager** → **Modules** → **Install**, lalu **Reboot**.
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
